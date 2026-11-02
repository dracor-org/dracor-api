xquery version "3.1";

(:~
 : Module for scheduling the jobs that keep the data derived from the TEI
 : documents (metrics, sitelinks, RDF, Fuseki graphs) in sync.
 :
 : This module is imported by the collection trigger, which eXist-db compiles
 : for every single trigger event. It must therefore stay lightweight and not
 : import any of the heavier modules.
 :)
module namespace queue = "http://dracor.org/ns/exist/v1/queue";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";

(: prefix of the names of all sync jobs :)
declare variable $queue:prefix := "sync-";

(:
 : Delay in ms before a sync job runs. Changes arriving within this time, e.g.
 : the several documents of a play stored by a corpus load, are handled by a
 : single job.
 :)
declare variable $queue:delay := 30000;

declare %private function queue:schedule-job(
  $name as xs:string,
  $script as xs:string,
  $params as element(parameters)
) as xs:boolean {
  scheduler:schedule-xquery-periodic-job(
    $config:app-root || "/jobs/" || $script,
    1,
    $name,
    $params,
    $queue:delay,
    0
  )
};

(:~
 : Schedule a job under the first of the given names that isn't taken by a
 : job that has already fired
 :
 : A job that hasn't fired yet will see the change it is scheduled for, so it
 : takes in further changes. A job that has fired may have read the data
 : before the change, so a follow-up job is needed. The trigger of a one-shot
 : job stays in state NORMAL while the job runs and is removed when it has
 : completed. Whether it has fired can only be told by its next fire time,
 : which is empty once it has fired.
 :)
declare %private function queue:schedule-first(
  $names as xs:string*,
  $script as xs:string,
  $params as element(parameters)
) as xs:boolean {
  if (empty($names)) then
    false()
  (: scheduling fails when a job of the same name exists :)
  else if (queue:schedule-job($names[1], $script, $params)) then
    true()
  else
    let $job := scheduler:get-scheduled-jobs()//scheduler:job[@name = $names[1]]
    return if (empty($job)) then
      (: either it has completed in the meantime or we may not schedule :)
      queue:schedule-job($names[1], $script, $params)
    else if ($job/scheduler:trigger/next[normalize-space()]) then
      true()
    else
      queue:schedule-first(subsequence($names, 2), $script, $params)
};

(:~
 : Schedule a job unless one with the same name is already waiting to run
 :
 : If the job of that name is already running, a follow-up job is scheduled
 : under the name suffixed with ":next", so that changes made while a sync is
 : running don't get lost. If that one is running too, a job with a unique
 : name is scheduled.
 :
 : Scheduling requires the dba role. For other users this does nothing; the
 : reconcile job catches what has been missed.
 :
 : @param $name Job name
 : @param $script Path of the job script relative to the app root
 : @param $params Job parameters
 :)
declare function queue:schedule(
  $name as xs:string,
  $script as xs:string,
  $params as element(parameters)
) as xs:boolean {
  queue:schedule-first(
    ($name, $name || ":next", $name || ":" || util:uuid()),
    $script,
    $params
  )
};

(:~
 : Schedule sync of a play
 :
 : @param $corpusname
 : @param $playname
 :)
declare function queue:sync-play(
  $corpusname as xs:string,
  $playname as xs:string
) as xs:boolean {
  queue:schedule(
    $queue:prefix || "play-" || $corpusname || "/" || $playname,
    "sync-play.xq",
    <parameters>
      <param name="corpusname" value="{ $corpusname }" />
      <param name="playname" value="{ $playname }" />
    </parameters>
  )
};

(:~
 : Schedule sync of a corpus
 :
 : @param $corpusname
 :)
declare function queue:sync-corpus($corpusname as xs:string) as xs:boolean {
  queue:schedule(
    $queue:prefix || "corpus-" || $corpusname,
    "sync-corpus.xq",
    <parameters><param name="corpusname" value="{ $corpusname }" /></parameters>
  )
};

(:~
 : Schedule the sync job matching a database path
 :
 : Paths of a corpus collection schedule a corpus sync, paths of a play
 : collection or its TEI document a play sync. All other paths are ignored.
 :
 : @param $uri Path of a collection or document
 :)
declare function queue:enqueue($uri as xs:anyURI) as xs:boolean? {
  let $prefix := $config:corpora-root || "/"
  (: the URI may be prefixed with xmldb:exist:// :)
  return if (contains($uri, $prefix)) then
    let $segments := tokenize(substring-after($uri, $prefix), "/")[. ne ""]
    return switch (count($segments))
      case 1 return
        queue:sync-corpus($segments[1])
      case 2 return
        (: documents of the corpus collection, e.g. corpus.xml :)
        if (ends-with($segments[2], ".xml")) then (
        ) else
          queue:sync-play($segments[1], $segments[2])
      case 3 return
        if ($segments[3] eq "tei.xml") then
          queue:sync-play($segments[1], $segments[2])
        else (
        )
      default return
        ()
  else (
  )
};

(:~
 : Number of pending or running sync jobs
 :)
declare function queue:pending() as xs:integer {
  count(
    scheduler:get-scheduled-jobs()//scheduler:job[starts-with(
      @name,
      $queue:prefix
    ) and
      scheduler:trigger/state != "COMPLETE"]
  )
};

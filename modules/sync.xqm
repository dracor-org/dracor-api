xquery version "3.1";

(:~
 : Module for keeping the data derived from the TEI documents in sync.
 :
 : For each play the metrics, the Wikidata sitelinks and the RDF are stored
 : next to the TEI document, and the RDF is put into a graph of its own in
 : Fuseki. Changes to the corpora collection are picked up by the collection
 : trigger, which schedules the jobs calling the functions of this module (see
 : queue.xqm).
 :
 : The sync functions look at the current state of the database rather than at
 : the change that caused them to be scheduled. This makes them idempotent and
 : independent of the order in which the jobs run.
 :
 : When a play has been synced successfully a sync.xml file recording the last
 : modification time of the TEI document is stored next to it. A play whose
 : sync.xml is missing or records a different time is considered pending.
 :)
module namespace sync = "http://dracor.org/ns/exist/v1/sync";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";
import module namespace metrics = "http://dracor.org/ns/exist/v1/metrics" at "metrics.xqm";
import module namespace drdf = "http://dracor.org/ns/exist/v1/rdf" at "rdf.xqm";
import module namespace queue = "http://dracor.org/ns/exist/v1/queue" at "queue.xqm";

(:
 : Modification time of the TEI document of a play, empty if there is none
 :
 : A tei.xml without a TEI root (like the old trigger, which ignored such
 : documents) is not considered a play, so that it doesn't stay pending.
 :)
declare %private function sync:tei-modified($paths as map(*)) as xs:dateTime? {
  if (doc-available($paths?files?tei) and doc($paths?files?tei)/tei:TEI) then
    xmldb:last-modified($paths?collections?play, "tei.xml")
  else (
  )
};

declare %private function sync:is-pending(
  $paths as map(*),
  $modified as xs:dateTime?
) as xs:boolean {
  exists($modified) and
    not(xs:dateTime(doc($paths?files?sync)/sync/@tei-modified) = $modified)
};

(:
 : Check whether the TEI document has changed since the sync read it, and if so
 : schedule another sync
 :
 : The change has scheduled a sync itself, but that may already be running
 : alongside this one, or the change may have been made by a user who can't
 : schedule jobs.
 :)
declare %private function sync:changed(
  $paths as map(*),
  $modified as xs:dateTime
) as xs:boolean {
  if (sync:tei-modified($paths) = $modified) then
    false()
  else
    let $log := util:log-system-out(
      "Sync: " || $paths?files?tei || " changed during sync, rescheduling"
    )
    let $scheduled := queue:sync-play($paths?corpusname, $paths?playname)
    return true()
};

declare %private function sync:record($paths as map(*), $modified) {
  xmldb:store(
    $paths?collections?play,
    "sync.xml",
    <sync tei-modified="{ $modified }" updated="{ current-dateTime() }" />
  )
};

(:~
 : Sync a play
 :
 : If the play exists its metrics, sitelinks and RDF are updated, otherwise its
 : graph is removed from Fuseki.
 :
 : Metrics and sitelinks are fetched before anything is stored. If the network
 : metrics can't be calculated (e.g. the metrics service fails), the previous
 : metrics are kept and the play stays pending, to be retried by reconcile.
 :
 : Two syncs of a play can run at the same time when the play changes while it
 : is being synced. A sync that finds the TEI document changed before it writes
 : anything, or after it has updated Fuseki, stops and schedules another one,
 : so that it doesn't overwrite newer data with older.
 :
 : @param $corpusname
 : @param $playname
 : @return true() on success
 :)
declare function sync:play(
  $corpusname as xs:string,
  $playname as xs:string
) as xs:boolean {
  let $paths := dutil:filepaths($corpusname, $playname)
  let $collection := $paths?collections?play
  let $url := $paths?files?tei
  let $modified := sync:tei-modified($paths)
  return if (empty($modified)) then
    let $log := util:log-system-out("Sync: " || $url || " is gone")
    let $dropped := drdf:fuseki-drop-play($corpusname, $playname)
    (: the collection may still exist when only the TEI has been deleted :)
    let $removed := if ($dropped and doc-available($paths?files?sync)) then
      xmldb:remove($collection, "sync.xml")
    else (
    )
    return $dropped
  else
    let $log := util:log-system-out("Sync: " || $url)
    let $tei := doc($url)/tei:TEI
    let $metrics := metrics:calculate($url)
    return if (empty($metrics/network/size)) then (
      util:log-system-out("Sync: network metrics failed for " || $url), false()
    ) else
      let $wikidata-id := dutil:get-play-wikidata-id($tei)
      let $sitelinks := if ($wikidata-id) then
        metrics:get-sitelinks($wikidata-id)
      else (
      )
      return if (sync:changed($paths, $modified)) then
        false()
      else
        (: the RDF includes the metrics, so they need to be stored first :)
        let $stored-metrics := xmldb:store($collection, "metrics.xml", $metrics)
        let $stored-sitelinks := if (exists($sitelinks)) then
          xmldb:store($collection, "sitelinks.xml", $sitelinks)
        (: remove sitelinks of a play that has lost its Wikidata ID :)
        else if (doc-available($paths?files?sitelinks)) then
          xmldb:remove($collection, "sitelinks.xml")
        else (
        )
        let $rdf := drdf:play-to-rdf($tei)
        return if (not(drdf:fuseki-put($corpusname, $playname, $rdf))) then (
          (: without sync.xml the play stays pending, reconcile retries it :)
          util:log-system-out("Sync: Fuseki update failed for " || $url),
          false()
        ) else if (sync:changed($paths, $modified)) then
          false()
        else
          (:
           : rdf.xml is only stored once Fuseki has been updated, since
           : reconcile takes a play without sync.xml whose rdf.xml is newer
           : than tei.xml for synced
           :)
          let $stored-rdf := xmldb:store($collection, "rdf.xml", $rdf)
          let $recorded := sync:record($paths, $modified)
          return true()
};

(:~
 : Sync a corpus
 :
 : Removes the graphs of all plays of a corpus from Fuseki if the corpus
 : doesn't exist (anymore). The plays of an existing corpus are synced
 : individually, but graphs of its plays that don't exist are removed, e.g.
 : when the corpus has been deleted and created again before this sync ran.
 :
 : @param $corpusname
 : @return true() on success
 :)
declare function sync:corpus($corpusname as xs:string) as xs:boolean {
  if (
    xmldb:collection-available($config:corpora-root || "/" || $corpusname)
  ) then
    let $dropped :=
      for $play in drdf:fuseki-plays()[?corpusname = $corpusname]
      where empty(
        sync:tei-modified(dutil:filepaths($corpusname, $play?playname))
      )
      return drdf:fuseki-drop-play($corpusname, $play?playname)
    return every $d in $dropped satisfies $d
  else (
    util:log-system-out("Sync: corpus " || $corpusname || " is gone"),
    drdf:fuseki-drop-corpus($corpusname)
  )
};

(:~
 : Check whether the derived data of a play is not up to date
 :
 : @param $corpusname
 : @param $playname
 :)
declare function sync:play-pending(
  $corpusname as xs:string,
  $playname as xs:string
) as xs:boolean {
  let $paths := dutil:filepaths($corpusname, $playname)
  return sync:is-pending($paths, sync:tei-modified($paths))
};

(:~
 : Check whether the derived data of any play of a corpus is not up to date
 :
 : @param $corpusname
 :)
declare function sync:corpus-pending($corpusname as xs:string) as xs:boolean {
  let $collection := $config:corpora-root || "/" || $corpusname
  return xmldb:collection-available($collection) and
    (
      some
        $playname in
        xmldb:get-child-collections($collection) satisfies
        sync:play-pending($corpusname, $playname)
    )
};

(:~
 : Check whether the derived data of any play is not up to date
 :)
declare function sync:pending() as xs:boolean {
  some
    $corpusname in
    xmldb:get-child-collections($config:corpora-root) satisfies
    sync:corpus-pending($corpusname)
};

(:~
 : Schedule sync for all plays whose derived data is not up to date, and for
 : all plays that still have a graph in Fuseki although they don't exist
 :
 : This catches what the sync jobs have missed, e.g. because the database was
 : restarted before a scheduled job could run, because Fuseki was not
 : available, or because the change was made by a user that is not allowed to
 : schedule jobs. Comparing the graphs in Fuseki with the plays in the database
 : also catches deleted plays (including TEI documents deleted without their
 : play collection, which the trigger ignores), since nothing is left of them
 : in the database.
 :
 : Plays without sync.xml whose RDF is newer than the TEI document and that
 : have a graph in Fuseki were synced before sync.xml was introduced. For these
 : sync.xml is just recorded. (Before, rdf.xml was stored even when the Fuseki
 : update failed, so a missing graph means the play wasn't synced.)
 :
 : The reconcile job is scheduled by post-install.xq to run shortly after each
 : deploy and then every hour. Since scheduled jobs are lost when eXist-db is
 : restarted, it should also be run from the scheduler in conf.xml.
 :
 : @return map with the number of recorded plays, of scheduled plays and of
 : scheduled plays that only have a graph left
 :)
declare function sync:reconcile() as map(*) {
  let $log := util:log-system-out("Sync: reconciling")
  let $fuseki-plays := drdf:fuseki-plays()
  let $graphs := $fuseki-plays!(?corpusname || "/" || ?playname)
  let $results :=
    for $corpusname in xmldb:get-child-collections($config:corpora-root)
    let $collection := $config:corpora-root || "/" || $corpusname
    for $playname in xmldb:get-child-collections($collection)
    let $paths := dutil:filepaths($corpusname, $playname)
    let $modified := sync:tei-modified($paths)
    where sync:is-pending($paths, $modified)
    return if (
      not(doc-available($paths?files?sync)) and
        doc-available($paths?files?metrics) and
        doc-available($paths?files?rdf) and
        xmldb:last-modified($paths?collections?play, "rdf.xml") >= $modified and
        ($corpusname || "/" || $playname) = $graphs
    ) then
      let $recorded := sync:record($paths, $modified)
      return "recorded"
    else
      let $scheduled := queue:sync-play($corpusname, $playname)
      return "scheduled"
  let $orphans :=
    for $play in $fuseki-plays
    let $paths := dutil:filepaths($play?corpusname, $play?playname)
    where empty(sync:tei-modified($paths))
    let $scheduled := queue:sync-play($play?corpusname, $play?playname)
    return "graph"
  let $result := map {
    "recorded": count($results[. = "recorded"]),
    "scheduled": count($results[. = "scheduled"]),
    "graphs": count($orphans)
  }
  return (
    util:log-system-out(
      "Sync: recorded " ||
        $result?recorded ||
        ", scheduled " ||
        $result?scheduled ||
        ", scheduled for left-over graphs " ||
        $result?graphs
    ),
    $result
  )
};

(:~
 : Response headers keeping a caching proxy from storing a response
 :
 : Responses including data derived from the TEI documents (metrics, sitelinks,
 : RDF) must not be cached while that data is pending. nginx doesn't cache
 : responses with a zero X-Accel-Expires header and doesn't pass that header on
 : to the client.
 :
 : @param $pending Whether the derived data is pending
 :)
declare function sync:cache-control($pending as xs:boolean) as element()? {
  if ($pending) then
    <rest:response>
      <http:response>
        <http:header name="X-Accel-Expires" value="0" />
      </http:response>
    </rest:response>
  else (
  )
};

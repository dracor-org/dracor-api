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

declare %private function sync:tei-modified($paths as map(*)) as xs:dateTime? {
  if (doc-available($paths?files?tei)) then
    xmldb:last-modified($paths?collections?play, "tei.xml")
  else (
  )
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
 : @param $corpusname
 : @param $playname
 : @return true() on success
 :)
declare function sync:play(
  $corpusname as xs:string,
  $playname as xs:string
) as xs:boolean {
  let $paths := dutil:filepaths($corpusname, $playname)
  let $url := $paths?files?tei
  let $modified := sync:tei-modified($paths)
  return if (empty($modified)) then
    let $log := util:log-system-out("Sync: " || $url || " is gone")
    let $dropped := drdf:fuseki-drop-play($corpusname, $playname)
    (: the collection may still exist when only the TEI has been deleted :)
    let $removed := if ($dropped and doc-available($paths?files?sync)) then
      xmldb:remove($paths?collections?play, "sync.xml")
    else (
    )
    return $dropped
  else
    let $log := util:log-system-out("Sync: " || $url)
    (: the RDF includes the metrics, so they need to be updated first :)
    let $metrics := metrics:update($url)
    let $sitelinks := metrics:update-sitelinks($url)
    (: remove sitelinks of a play that has lost its Wikidata ID :)
    let $removed := if (
      empty($sitelinks) and doc-available($paths?files?sitelinks)
    ) then
      xmldb:remove($paths?collections?play, "sitelinks.xml")
    else (
    )
    let $rdf := drdf:play-to-rdf(doc($url)/tei:TEI)
    let $stored := xmldb:store($paths?collections?play, "rdf.xml", $rdf)
    return if (drdf:fuseki-put($corpusname, $playname, $rdf)) then (
      let $recorded := sync:record($paths, $modified)
      return true()
    ) else (
      (: without sync.xml the play stays pending and is retried by reconcile :)
      util:log-system-out("Sync: Fuseki update failed for " || $url), false()
    )
};

(:~
 : Sync a corpus
 :
 : Removes the graphs of all plays of a corpus from Fuseki if the corpus
 : doesn't exist (anymore). The plays of an existing corpus are synced
 : individually.
 :
 : @param $corpusname
 : @return true() on success
 :)
declare function sync:corpus($corpusname as xs:string) as xs:boolean {
  if (
    xmldb:collection-available($config:corpora-root || "/" || $corpusname)
  ) then
    true()
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
  let $modified := sync:tei-modified($paths)
  return exists($modified) and
    not(xs:dateTime(doc($paths?files?sync)/sync/@tei-modified) = $modified)
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
 : Plays without sync.xml whose RDF is newer than the TEI document were synced
 : before sync.xml was introduced. For these sync.xml is just recorded.
 :
 : The reconcile job runs after each deploy. It must run regularly (e.g. from
 : the scheduler in conf.xml) to catch what was missed in between.
 :
 : @return map with the number of recorded plays, of scheduled plays and of
 : scheduled plays that only have a graph left
 :)
declare function sync:reconcile() as map(*) {
  let $log := util:log-system-out("Sync: reconciling")
  let $results :=
    for $corpusname in xmldb:get-child-collections($config:corpora-root)
    let $collection := $config:corpora-root || "/" || $corpusname
    for $playname in xmldb:get-child-collections($collection)
    let $paths := dutil:filepaths($corpusname, $playname)
    let $modified := sync:tei-modified($paths)
    where sync:play-pending($corpusname, $playname)
    return if (
      not(doc-available($paths?files?sync)) and
        doc-available($paths?files?metrics) and
        doc-available($paths?files?rdf) and
        xmldb:last-modified($paths?collections?play, "rdf.xml") >= $modified
    ) then
      let $recorded := sync:record($paths, $modified)
      return "recorded"
    else
      let $scheduled := queue:sync-play($corpusname, $playname)
      return "scheduled"
  let $graphs :=
    for $play in drdf:fuseki-plays()
    let $paths := dutil:filepaths($play?corpusname, $play?playname)
    where not(doc-available($paths?files?tei))
    let $scheduled := queue:sync-play($play?corpusname, $play?playname)
    return "graph"
  let $result := map {
    "recorded": count($results[. = "recorded"]),
    "scheduled": count($results[. = "scheduled"]),
    "graphs": count($graphs)
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

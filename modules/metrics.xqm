xquery version "3.1";

(:~
 : Module for calculating and updating corpus metrics.
 :)
module namespace metrics = "http://dracor.org/ns/exist/v1/metrics";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace cache = "http://exist-db.org/xquery/cache";
import module namespace xdb = "http://exist-db.org/xquery/xmldb";
import module namespace util = "http://exist-db.org/xquery/util";
import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";
import module namespace wd = "http://dracor.org/ns/exist/v1/wikidata" at "wikidata.xqm";

(:~
 : How long the service metadata stays in the cache
 :)
declare variable $metrics:service-info-ttl := xs:dayTimeDuration("PT10M");

(:~
 : Turn the service metadata the metrics service sends into the map the API
 : returns, leaving out what an older service doesn't send.
 :
 : @param $service Map with keys service, version and networkx
 :)
declare function metrics:service-map($service as map(*)) as map(*) {
  map:merge(
    (
      map:entry("name", $service?service),
      map:entry("version", $service?version),
      if (exists($service?networkx)) then
        map:entry("networkx", $service?networkx)
      else (
      )
    )
  )
};

(:~
 : Store the service metadata in the cache.
 :
 : @param $json Service metadata as JSON, empty string if unavailable
 :)
declare function metrics:cache-service-info($json as xs:string) {
  cache:put("dracor-metrics", "service", (current-dateTime(), $json))
};

(:~
 : Fetch the service metadata from the root of the metrics service.
 :
 : @return Service metadata as JSON, empty string if unavailable
 :)
declare function metrics:fetch-service-info() as xs:string {
  let $url := replace($config:metrics-server, "metrics/?$", "")
  let $response := try {
    hc:send-request(<hc:request href="{ $url }" method="get" timeout="2" />)
  } catch * {
    util:log-system-out(
      "metrics service info request failed: " || $err:description
    )
  }
  return if (string($response[1]/@status) = "200") then
    util:base64-decode($response[2])
  else
    ""
};

(:~
 : Get name and versions of the currently configured metrics service.
 :
 : The metadata is cached for $metrics:service-info-ttl, including a failed
 : request, so that the API info endpoint doesn't wait for the metrics service
 : each time.
 :
 : @return Map with name, version and networkx, empty if unavailable
 :)
declare function metrics:service-info() as map(*)? {
  let $cached := cache:get("dracor-metrics", "service")
  let $json := if (
    exists($cached) and
      current-dateTime() - $cached[1] lt $metrics:service-info-ttl
  ) then
    $cached[2]
  else
    let $json := metrics:fetch-service-info()
    let $cache := metrics:cache-service-info($json)
    return $json
  return if ($json ne "") then
    metrics:service-map(parse-json($json))
  else (
  )
};

(:~
 : Query sitelinks for given Wikidata ID and store them to the play
 : collection.
 :
 : @param $id Wikidata ID
 : @param $collection Path to play collection
 :)
declare function metrics:update-sitelinks(
  $id as xs:string,
  $collection as xs:string
) {
  if ($id ne "") then
    let $log := util:log-system-out("querying sitelinks for " || $collection)
    let $sitelinks := <sitelinks id="{ $id }" updated="{ current-dateTime() }">
      {
        for $uri in wd:get-sitelinks($id)
        return <uri>{ $uri }</uri>
      }
    </sitelinks>
    return ($sitelinks, xmldb:store($collection, "sitelinks.xml", $sitelinks))
  else (
  )
};

(:~
 : Update sitelinks for Wikidata ID of play with given url.
 :
 : @param $url Path to TEI file
 :)
declare function metrics:update-sitelinks($url as xs:string) {
  let $p := dutil:filepaths($url)
  let $doc := dutil:get-doc($p?corpusname, $p?playname)
  let $id := dutil:get-play-wikidata-id($doc/tei:TEI)
  return if ($id) then
    metrics:update-sitelinks($id, $p?collections?play)
  else (
  )
};

(:~
 : Collect sitelinks for each play in a given corpus from wikidata and store
 : them to the respective play collections
 :
 : @param $corpus Corpus name
 :)
declare function metrics:collect-sitelinks($corpus as xs:string) {
  util:log-system-out("collecting sitelinks for corpus " || $corpus),
  let $collection := $config:corpora-root || "/" || $corpus
  (: DEPRECATED: remove standOff support in v2 :)
  for $tei in
    collection(
      $collection
    )/tei:TEI[tei:teiHeader//tei:sourceDesc/tei:bibl[@type =
      "wikidata"]/tei:idno or
      tei:standOff/tei:listRelation/tei:relation[@name = "wikidata"]/@passive]
  return metrics:update-sitelinks($tei/base-uri())
};

(:~
 : Collect sitelinks for all corpora from wikidata and store them to the
 : sitelinks collection
 :)
declare function metrics:collect-sitelinks() {
  (: DEPRECATED: remove teiCorpus support in v2 :)
  for $corpus in
    collection($config:corpora-root)/(tei:dracorCorpus | tei:teiCorpus)
  let $info := dutil:get-corpus-info($corpus)
  return metrics:collect-sitelinks($info?name)
};

(:~
 : Calculate network metrics for single play
 :
 : @param $url URL of the TEI document
 :)
declare function metrics:get-network-metrics($url as xs:string) {
  let $tei := doc($url)/tei:TEI
  let $num-speakers := count($tei//tei:sp/@who)

  return if ($num-speakers = 0) then
    (: when there are no speakers there is no network hence no calculation :)
    <network><size>0</size></network>
  else
    let $segments := map {
      "segments":
        array
          {
            for $segment in dutil:get-segments($tei)
            let $speakers := dutil:distinct-speakers($segment)
            return map {
              "speakers":
                array
                  {
                    for $sp in $speakers
                    return $sp
                  }
            }
          }
    }

    let $payload := serialize(
      $segments,
      <output:serialization-parameters>
        <output:method>json</output:method>
      </output:serialization-parameters>
    )

    (:
     : Since the metrics service cannot properly handle chunked transfer encoding
     : we disable it using the undocumented @chunked attribute.
     : see https://github.com/expath/expath-http-client-java/issues/9
     :)
    let $request := <hc:request chunked="false" method="post">
      <hc:body media-type="application/json" method="text" />
    </hc:request>
    let $response := hc:send-request(
      $request,
      ($config:metrics-server || "?" || $url),
      $payload
    )
    let $status := string($response[1]/@status)
    let $metrics := if ($status = "200") then
      $response[2] => util:base64-decode() => parse-json()
    else (
      util:log-system-out(
        "metrics service FAILED with status '" || $status || "' for " || $url
      ),
      map {}
    )

    let $service := $metrics?service
    let $cache := if (exists($service)) then
      metrics:cache-service-info(serialize($service, map {"method": "json"}))
    else (
    )

    return <network>
      {
        if (exists($service)) then (
          attribute service { $service?service },
          attribute version { $service?version },
          attribute networkx { $service?networkx }
        ) else (
        ),
        for $k in map:keys($metrics)[. ne "service"]
        return element {$k} {
          if ($k eq "nodes") then
            for $id in map:keys($metrics?nodes)
            return <node id="{ $id }">
              {
                for $n in map:keys($metrics($k)($id))
                return element {$n} { $metrics($k)($id)($n) }
              }
            </node>
          else
            $metrics($k)
        }
      }
    </network>
};

(:~
 : Calculate metrics for single play
 :
 : @param $url URL of the TEI document
 :)
declare function metrics:calculate($url as xs:string) {
  let $separator := "\W+"
  let $doc := doc($url)
  let $text-count := count(tokenize($doc/tei:TEI/tei:text[1], $separator))
  let $stage-count := count(
    tokenize(string-join($doc//tei:stage, " "), $separator)
  )
  let $sp-count := count(tokenize(string-join($doc//tei:sp, " "), $separator))
  return <metrics updated="{ current-dateTime() }">
    <text>{ $text-count }</text>
    <stage>{ $stage-count }</stage>
    <sp>{ $sp-count }</sp>
    { metrics:get-network-metrics($url) }
  </metrics>
};

(:~
 : Update metrics for single play
 :
 : @param $url URL of the TEI document
 :)
declare function metrics:update($url as xs:string) {
  let $metrics := metrics:calculate($url)
  let $paths := dutil:filepaths($url)
  let $collection := $paths?collections?play
  return (
    util:log-system-out("Metrics update: " || $paths?files?metrics),
    xdb:store($collection, "metrics.xml", $metrics)
  )
};

(:~
 : Update metrics for all plays in the database
 :)
declare function metrics:update() as xs:string* {
  let $l := util:log-system-out("Updating metrics files")
  for $tei in collection($config:corpora-root)//tei:TEI
  let $url := $tei/base-uri()
  return metrics:update($url)
};

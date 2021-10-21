xquery version "3.1";

(:~
 : Module for calculating and updating corpus metrics.
 :)
module namespace metrics = "http://dracor.org/ns/exist/metrics";

import module namespace xdb = "http://exist-db.org/xquery/xmldb";
import module namespace util = "http://exist-db.org/xquery/util";
import module namespace config = "http://dracor.org/ns/exist/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";
import module namespace wd = "http://dracor.org/ns/exist/wikidata" at "wikidata.xqm";

declare namespace trigger = "http://exist-db.org/xquery/trigger";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Collect sitelinks for each play in a given corpus from wikidata and store
 : them to the sitelinks collection
 :
 : @param $corpus Corpus name
:)
declare function metrics:collect-sitelinks($corpus as xs:string) {
  let $log := util:log('info', 'collecting sitelinks for corpus ' || $corpus)
  let $data-col := $config:data-root || '/' || $corpus
  let $sitelinks-col := xmldb:create-collection(
    "/", $config:sitelinks-root || '/' || $corpus
  )
  let $idnos := collection($data-col)
    /tei:TEI//tei:publicationStmt/tei:idno[@type="wikidata"]/text()
  for $id in $idnos
  let $resource := $id || '.xml'
  let $log := util:log('info', 'querying sitelinks for ' || $resource)
  let $sitelinks := <sitelinks id="{$id}" updated="{current-dateTime()}">{
    for $uri in wd:get-sitelinks($id)
    return <uri>{$uri}</uri>
  }</sitelinks>
  return xmldb:store($sitelinks-col, $resource, $sitelinks)
};

(:~
 : Collect sitelinks for all corpora from wikidata and store them to the
 : sitelinks collection
:)
declare function metrics:collect-sitelinks() {
  for $corpus in collection($config:data-root)//tei:teiCorpus
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
    "segments": array {
      for $segment in dutil:get-segments($tei)
      let $speakers := dutil:distinct-speakers($segment)
      return map {
        "speakers": array {
          for $sp in $speakers return $sp
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

  (: Since the metrics service cannot properly handle chunked transfer encoding
   : we disable it using the undocumented @chunked attribute.
   : see https://github.com/expath/expath-http-client-java/issues/9 :)
  let $request :=
    <hc:request method="post" chunked="false">
      <hc:body media-type="application/json" method="text"/>
    </hc:request>
  let $response := hc:send-request($request, ($config:metrics-server || '?' || $url), $payload)
  let $status := string($response[1]/@status)
  let $metrics := if ($status = "200") then
    $response[2] => util:base64-decode() => parse-json()
  else (
    util:log(
      "warn",
      "metrics service FAILED with status '"|| $status ||"' for " || $url
    ),
    map{}
  )

  return
    <network>
      {
        for $k in map:keys($metrics)
        return element {$k} {
          if($k eq "nodes") then
            for $id in map:keys($metrics?nodes )
            return
            <node id="{$id}">
              {
                for $n in map:keys($metrics($k)($id))
                return element {$n} {$metrics($k)($id)($n)}
              }
            </node>
          else $metrics($k)
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
  let $separator := '\W+'
  let $doc := doc($url)
  let $text-count := count(tokenize($doc//tei:text, $separator))
  let $stage-count := count(tokenize(string-join($doc//tei:stage, ' '), $separator))
  let $sp-count := count(tokenize(string-join($doc//tei:sp, ' '), $separator))
  return <metrics updated="{current-dateTime()}">
    <text>{$text-count}</text>
    <stage>{$stage-count}</stage>
    <sp>{$sp-count}</sp>
    {metrics:get-network-metrics($url)}
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
  let $collection := $paths?collections?metrics
  let $resource := $paths?filename
  return (
    util:log('info', ('Metrics update: ', $collection, "/", $resource)),
    xdb:store($collection, $resource, $metrics)
  )
};

(:~
 : Update metrics for all plays in the database
:)
declare function metrics:update() as xs:string* {
  let $l := util:log-system-out("Updating metrics files")
  for $tei in collection($config:data-root)//tei:TEI
  let $url := $tei/base-uri()
  return metrics:update($url)
};

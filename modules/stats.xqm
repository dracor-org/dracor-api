xquery version "3.0";

(:~
 : Module for calculating and updating corpus stats.
 :)
module namespace stats = "http://dracor.org/ns/exist/stats";

import module namespace xdb = "http://exist-db.org/xquery/xmldb";
import module namespace config="http://dracor.org/ns/exist/config" at "config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Calculate stats for single play
 :
 : @param $url URL of the TEI document
:)
declare function stats:calculate($url as xs:string) {
  let $separator := '\W+'
  let $doc := doc($url)
  let $text-count := count(tokenize($doc//tei:text, $separator))
  let $stage-count := count(tokenize(string-join($doc//tei:stage, ' '), $separator))
  let $sp-count := count(tokenize(string-join($doc//tei:sp, ' '), $separator))
  return <stats updated="{current-dateTime()}">
    <text>{$text-count}</text>
    <stage>{$stage-count}</stage>
    <sp>{$sp-count}</sp>
  </stats>
};

(:~
 : Update stats for single play
 :
 : @param $url URL of the TEI document
:)
declare function stats:update($url as xs:string) {
  let $stats := stats:calculate($url)
  let $filename := tokenize($url, '/')[last()]
  let $stats-url := replace($url, $config:data-root, $config:stats-root)
  let $collection := replace($stats-url, '/[^/]+$', '')

  let $c := xdb:create-collection('/', $collection)

  return xdb:store($collection, $filename, $stats)
};

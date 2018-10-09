xquery version "3.1";

module namespace api = "http://dracor.org/ns/exist/api";

import module namespace config = "http://dracor.org/ns/exist/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";
import module namespace load = "http://dracor.org/ns/exist/load" at "load.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace repo = "http://exist-db.org/xquery/repo";
declare namespace expath = "http://expath.org/ns/pkg";
declare namespace json = "http://www.w3.org/2013/XSL/json";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace jsn="http://www.json.org";


declare function local:get-info () {
  let $expath := config:expath-descriptor()
  let $repo := config:repo-descriptor()
  return
    <info>
      <name>{$expath/expath:title/string()}</name>
      <version>{$expath/@version/string()}</version>
      <status>{$repo/repo:status/string()}</status>
      <existdb>{system:get-version()}</existdb>
    </info>
};

declare
  %rest:GET
  %rest:path("/info")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:darcor() {
  local:get-info()
};

declare
  %rest:GET
  %rest:path("/info.xml")
  %rest:produces("application/xml")
function api:info-xml() {
  local:get-info()
};

declare
  %rest:GET
  %rest:path("/resources")
  %rest:produces("application/xml", "text/xml")
function api:resources() {
  rest:resource-functions()
};

declare function local:get-index-keys ($collection as xs:string, $elem as xs:string) {
  <terms element="{$elem}" collection="{$collection}">
    {
      util:index-keys(
        collection($collection)//tei:*[name() eq $elem], "",
        function($key, $count) {
          <term name="{$key}" count="{$count[1]}"docs="{$count[2]}" pos="{$count[3]}"/>
        },
        -1,
        "lucene-index"
      )
    }
  </terms>
};

declare function local:get-corpus-metrics ($corpus as xs:string) {
  let $collection-uri := concat($config:data-root, "/", $corpus)
  let $col := collection($collection-uri)
  let $stats-uri := concat($config:stats-root, "/", $corpus)
  let $stats := collection($stats-uri)
  let $num-plays := count($col/tei:TEI)
  let $num-characters := count($col//tei:listPerson/tei:person)
  let $num-male := count($col//tei:listPerson/tei:person[@sex="MALE"])
  let $num-female := count($col//tei:listPerson/tei:person[@sex="FEMALE"])
  let $num-text := count($col//tei:text)
  let $num-stage := count($col//tei:stage)
  let $num-sp := count($col//tei:sp)
  return
  <metrics collection="{$collection-uri}">
    <plays>{$num-plays}</plays>
    <characters>{$num-characters}</characters>
    <male>{$num-male}</male>
    <female>{$num-female}</female>
    <text>{$num-text}</text>
    <sp>{$num-sp}</sp>
    <stage>{$num-stage}</stage>
    <wordcount>
      <text>{sum($stats//text)}</text>
      <sp>{sum($stats//sp)}</sp>
      <stage>{sum($stats//stage)}</stage>
    </wordcount>
    <updated>{max($stats//stats/xs:dateTime(@updated))}</updated>
  </metrics>
};

declare
  %rest:GET
  %rest:path("/metrics")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:metrics() {
    let $expath := config:expath-descriptor()
    let $repo := config:repo-descriptor()
    return
      <json>
        {
          for $corpus in $config:corpora//corpus
          return
          <metrics>
            <corpus>{$corpus/title, $corpus/name}</corpus>
            {
              for $m in local:get-corpus-metrics($corpus/name/text())/*
              return $m
            }
          </metrics>
        }
      </json>
};

declare
  %rest:GET
  %rest:path("/corpus")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora() {
  for $corpus in $config:corpora//corpus
  order by $corpus/name
  return map {
    "name" := $corpus/name/text(),
    "title" := $corpus/title/text()
  }
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:index($corpusname) {
  let $title := $config:corpora//corpus[name=$corpusname]/title/text()
  let $collection := concat($config:data-root, "/", $corpusname)
  let $col := collection($collection)
  return
    if (not($col)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      <index>
        <title>{$title}</title>
        {
          for $tei in $col//tei:TEI
          let $filename := tokenize(base-uri($tei), "/")[last()]
          let $id := tokenize($filename, "\.")[1]
          let $subtitle := $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
          let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
          let $authors := $tei//tei:fileDesc/tei:titleStmt/tei:author
          let $play-uri :=
            $config:api-base || "/corpus/" || $corpusname || "/play/" || $id
          order by $authors[1]
          return
            <dramas json:array="true">
              <id>{$id}</id>
              <title>
                {$tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space() }
              </title>
              {if ($subtitle) then <subtitle>{$subtitle}</subtitle> else ''}
              <author key="{$tei//tei:titleStmt/tei:author/@key}">
                <name>{$authors/string()}</name>
              </author>
              {
                for $author in $authors
                return
                  <authors key="{$author/@key}" json:array="true">
                    <name>{$author/string()}</name>
                  </authors>
              }
              <source>
                {$tei//tei:sourceDesc/tei:bibl[@type="digitalSource"]/tei:name/string()}
              </source>
              <sourceUrl>
                {
                  $tei//tei:sourceDesc/tei:bibl[@type="digitalSource"]
                    /tei:idno[@type="URL"]/string()
                }
              </sourceUrl>
              <printYear>{$dates[@type="print"]/@when/string()}</printYear>
              <premiereYear>{$dates[@type="premiere"]/@when/string()}</premiereYear>
              <writtenYear>{$dates[@type="written"]/@when/string()}</writtenYear>
              <networkdataCsvUrl>{$play-uri}/networkdata/csv</networkdataCsvUrl>
              <wikidataId>
                {$tei//tei:publicationStmt/tei:idno[@type="wikidata"]/string()}
              </wikidataId>
            </dramas>
        }
      </index>
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/metadata.csv")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:corpus-meta-data($corpusname) {
  let $meta := dutil:corpus-meta-data($corpusname)
  let $header := concat(string-join($meta[1]/*/name(), ','), "&#10;")
  let $data := for $row in $meta return concat(string-join($row/*/string(), ','), "&#10;")
  return ($header, $data)
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/load")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:load-corpus($corpusname) {
  let $loaded := load:load-corpus($corpusname)
  return
    if (not($loaded)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      <object>
        {
          for $doc in $loaded/doc
          return <loaded>{$doc/text()}</loaded>
        }
      </object>
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/word-frequencies/{$elem}")
  %rest:produces("application/xml", "text/xml")
function api:word-frequencies-xml($corpusname, $elem) {
  let $collection := concat($config:data-root, "/", $corpusname)
  let $terms := local:get-index-keys($collection, $elem)
  return $terms
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/word-frequencies/{$elem}")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:word-frequencies-csv($corpusname, $elem) {
  let $collection := concat($config:data-root, "/", $corpusname)
  let $terms := local:get-index-keys($collection, $elem)
  for $t in $terms/term
  order by number($t/@count) descending
  return concat($t/@name, ", ", $t/@count, ", ", $t/@docs, "&#10;")
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/play/{$playname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:play-info($corpusname, $playname) {
  let $info := dutil:play-info($corpusname, $playname)
  return
    if ($info) then
      $info
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/play/{$playname}/tei")
  %rest:produces("application/xml", "text/xml")
  %output:media-type("application/xml")
function api:play-tei($corpusname, $playname) {
  let $doc := doc(
    $config:data-root || "/" || $corpusname || "/" || $playname || ".xml"
  )
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $tei := $doc//tei:TEI
      let $target := 'xml-stylesheet'
      let $content := 'type="text/css" href="https://dracor.org/tei.css"'
      return document {
        processing-instruction {$target} {$content},
        $tei
      }
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/play/{$playname}/networkdata/csv")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:networkdata-csv($corpusname, $playname) {
  let $doc := doc(
    $config:data-root || "/" || $corpusname || "/" || $playname || ".xml"
  )
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $cast := dutil:distinct-speakers($doc//tei:body)
      let $segments :=
        <segments>
          {
            for $seg in $doc//tei:body//tei:div[tei:sp]
            return
              <sgm>
                {
                  for $id in dutil:distinct-speakers($seg)
                  return <spkr>{$id}</spkr>
                }
              </sgm>
          }
        </segments>

      let $links := map:new(
        for $spkr in $cast
        let $cooccurences := $segments//sgm[spkr=$spkr]/spkr/text()
        return map:entry($spkr, distinct-values($cooccurences)[.!=$spkr])
      )

      let $rows :=
        for $spkr at $pos in $cast
          for $cooc in $links($spkr)
          where index-of($cast, $cooc)[1] gt $pos
          let $weight := $segments//sgm[spkr=$spkr][spkr=$cooc] => count()
          return string-join(($spkr, 'Undirected',$cooc, $weight), ",")

      return string-join(("Source,Type,Target,Weight", $rows), "&#10;")
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/play/{$playname}/networkdata/gexf")
  %output:method("xml")
function api:networkdata-gefx($corpusname, $playname) {
  let $doc := doc(
    $config:data-root || "/" || $corpusname || "/" || $playname || ".xml"
  )
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $cast := dutil:distinct-speakers($doc//tei:body)
      let $segments :=
        <segments>
          {
            for $seg in $doc//tei:body//tei:div[tei:sp]
            return
              <sgm>
                {
                  for $id in dutil:distinct-speakers($seg)
                  return <spkr>{$id}</spkr>
                }
              </sgm>
          }
        </segments>

      let $info := dutil:play-info($corpusname, $playname)
      let $authors := $info/authors/name/text()
      let $title := $info/title/text()

      let $links := map:new(
        for $spkr in $cast
        let $cooccurences := $segments//sgm[spkr=$spkr]/spkr/text()
        return map:entry($spkr, distinct-values($cooccurences)[.!=$spkr])
      )

      let $nodes :=
        for $n in $info/cast
        let $id := $n/id/text()
        let $label := $n/name/text()
        return
          <node xmlns="http://www.gexf.net/1.2draft"
            id="{$id}" label="{$label}"/>

      let $edges :=
        for $spkr at $pos in $cast
          for $cooc in $links($spkr)
          where index-of($cast, $cooc)[1] gt $pos
          let $weight := $segments//sgm[spkr=$spkr][spkr=$cooc] => count()
          return
            <edge xmlns="http://www.gexf.net/1.2draft"
            id="{$spkr}|{$cooc}" source="{$spkr}" target="{$cooc}"
            weight="{$weight}"/>

      return
        <gexf xmlns="http://www.gexf.net/1.2draft" version="1.2">
          <meta>
            <creator>dracor.org</creator>
            <description>{$authors}: {$title}</description>
          </meta>
          <graph mode="static" defaultedgetype="undirected">
            <nodes>{$nodes}</nodes>
            <edges>{$edges}</edges>
          </graph>
        </gexf>
};

declare
  %rest:GET
  %rest:path("/corpus/{$corpusname}/play/{$playname}/segmentation")
  %rest:produces("application/xml", "text/xml")
  %output:media-type("text/xml")
function api:segmentation($corpusname, $playname) {
  let $doc := doc(
    $config:data-root || "/" || $corpusname || "/" || $playname || ".xml"
  )
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $cast := dutil:distinct-speakers($doc//tei:body)
      let $lastone := $cast[last()]
      let $divs := dutil:get-segments($doc//tei:TEI)
      let $segments :=
        <segments count="{count($divs)}">
          {
            for $seg at $pos in $divs
            let $heads := $seg/(ancestor::tei:div/tei:head|tei:head)
            return
            <sgm n="{$pos}" type="{$seg/@type}" title="{string-join($heads, ' | ')}">
              {
                for $id in dutil:distinct-speakers($seg)
                return <spkr>{$id}</spkr>
              }
            </sgm>
          }
        </segments>

      let $all-in-segment :=
        count($segments//sgm[spkr=$lastone][1]/preceding-sibling::sgm) + 1
      let $all-in-index := $all-in-segment div count($divs)

      return
      <segmentation
        all-in-index="{$all-in-index}"
        all-in-segment="{$all-in-segment}">
        <cast>
          {
            for $id in $cast
            let $name := $doc//tei:particDesc//(
              tei:person[@xml:id=$id]/tei:persName[1] |
              tei:personGrp[@xml:id=$id]/tei:name[1] |
              tei:persName[@xml:id=$id]
            )/text()
            return <member id="{$id}">{$name}</member>
          }
        </cast>
        {$segments}
      </segmentation>
};

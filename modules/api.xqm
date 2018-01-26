xquery version "3.1";

module namespace api = "http://dracor.org/ns/exist/api";

import module namespace config = "http://dracor.org/ns/exist/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace repo = "http://exist-db.org/xquery/repo";
declare namespace expath = "http://expath.org/ns/pkg";
declare namespace json = "http://www.w3.org/2013/XSL/json";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace jsn="http://www.json.org";

declare
  %rest:GET
  %rest:path("/dracor")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:darcor() {
    let $expath := config:expath-descriptor()
    let $repo := config:repo-descriptor()
    return
      <info>
        <name>{$expath/expath:title/string()}</name>
        <version>{$expath/@version/string()}</version>
        <status>{$repo/repo:status/string()}</status>
      </info>
};

declare
  %rest:GET
  %rest:path("/info.xml")
  %rest:produces("application/xml")
function api:info-xml() {
    let $expath := config:expath-descriptor()
    let $repo := config:repo-descriptor()
    return
      <info>
        <name>{$expath/expath:title/string()}</name>
        <version>{$expath/@version/string()}</version>
        <status>{$repo/repo:status/string()}</status>
      </info>
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
  %rest:path("/corpus/{$corpusname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:index($corpusname) {
  let $title := $config:corpora//corpus[name=$corpusname]/title/text()
  let $collection := concat($config:data-root, "/", $corpusname)
  return
  <index>
    {
      for $tei in collection($collection)//tei:TEI
      let $filename := tokenize(base-uri($tei), "/")[last()]
      let $id := tokenize($filename, "\.")[1]
      let $subtitle := $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
      let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
      let $play-uri :=
        $config:api-base || "/corpus/" || $corpusname || "/play/" || $id
      return
        <dramas json:array="true">
          <id>{$id}</id>
          <title>
            {$tei//tei:titleStmt/tei:title[1]/normalize-space() }
          </title>
          {if ($subtitle) then <subtitle>{$subtitle}</subtitle> else ''}
          <author key="{$tei//tei:titleStmt/tei:author/@key}">
            <name>{$tei//tei:titleStmt/tei:author/string()}</name>
          </author>
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
        </dramas>
    }
    <title>{$title}</title>
  </index>
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
      let $subtitle := $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
      let $cast := dutil:distinct-speakers($doc//tei:body)
      let $lastone := $cast[last()]
      let $segments :=
        <root>
        {
          for $segment in $tei//tei:div[tei:sp or @type="scene"]
          let $heads := $segment/(ancestor::tei:div/tei:head|tei:head)
          return
          <segments json:array="true">
            <type>{$segment/@type/string()}</type>
            {if ($heads) then <title>{string-join($heads, ' | ')}</title> else ()}
            {
              for $sp in dutil:distinct-speakers($segment)
              return
              <speakers json:array="true">{$sp}</speakers>
            }
          </segments>}
        </root>

      (: number of segment where last character appears :)
      let $all-in-segment := count(
        $segments//segments[speakers=$lastone][1]/preceding-sibling::segments
      ) + 1
      let $all-in-index := $all-in-segment div count($segments//segments)

      return
      <info>
        <id>{$playname}</id>
        <corpus>{$corpusname}</corpus>
        <title>
          {$tei//tei:titleStmt/tei:title[1]/normalize-space()}
        </title>
        {if ($subtitle) then <subtitle>{$subtitle}</subtitle> else ''}
        <author key="{$tei//tei:titleStmt/tei:author/@key}">
          <name>{$tei//tei:titleStmt/tei:author/string()}</name>
        </author>
        <allInSegment>{$all-in-segment}</allInSegment>
        <allInIndex>{$all-in-index}</allInIndex>
        {
          for $id in $cast
          let $name := $doc//tei:particDesc//(
            tei:person[@xml:id=$id]/tei:persName[1] |
            tei:persName[@xml:id=$id]
          )/text()
          return
          <cast json:array="true">
            <id>{$id}</id>
            {if($name) then <name>{$name}</name> else ()}
          </cast>
        }
        {$segments//segments}
      </info>
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
      let $divs := $doc//tei:body//tei:div[tei:sp or @type="scene"]
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
            let $name := $doc//tei:particDesc//(tei:person[@xml:id=$id]/tei:persName[1]|tei:persName[@xml:id=$id])/text()
            return <member id="{$id}">{$name}</member>
          }
        </cast>
        {$segments}
      </segmentation>
};

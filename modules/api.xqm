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

(: Namespaces for Linked Open Data :)
declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";
declare namespace rdfs="http://www.w3.org/2000/01/rdf-schema#" ;
declare namespace owl="http://www.w3.org/2002/07/owl#";
declare namespace dracon="http://dracor.org/ontology#";
(: /Namespaces for Linked Open Data :)




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
  %rest:path("/corpora")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora() {
  for $corpus in $config:corpora//corpus
  let $name := $corpus/name/text()
  order by $name
  return map {
    "name" := $name,
    "title" := $corpus/title/text(),
    "uri" := $config:api-base || '/corpora/' || $name
  }
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}")
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
            $config:api-base || "/corpora/" || $corpusname || "/play/" || $id
          let $stats-url :=
            $config:stats-root || "/" || $corpusname || "/" || $filename
          let $network-size := doc($stats-url)//network/size/text()
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
              <networkSize>{$network-size}</networkSize>
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
  %rest:path("/corpora/{$corpusname}/metadata.csv")
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
  %rest:path("/corpora/{$corpusname}/load")
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
  %rest:path("/corpora/{$corpusname}/word-frequencies/{$elem}")
  %rest:produces("application/xml", "text/xml")
function api:word-frequencies-xml($corpusname, $elem) {
  let $collection := concat($config:data-root, "/", $corpusname)
  let $terms := local:get-index-keys($collection, $elem)
  return $terms
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/word-frequencies/{$elem}")
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
  %rest:path("/corpora/{$corpusname}/play/{$playname}")
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
  %rest:path("/corpora/{$corpusname}/play/{$playname}/tei")
  %rest:produces("application/xml", "text/xml")
  %output:media-type("application/xml")
function api:play-tei($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
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
  %rest:path("/corpora/{$corpusname}/play/{$playname}/networkdata/csv")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:networkdata-csv($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
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
  %rest:path("/corpora/{$corpusname}/play/{$playname}/networkdata/gexf")
  %output:method("xml")
  %output:omit-xml-declaration("no")
function api:networkdata-gefx($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
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
        let $sex := $n/sex/text()
        let $group := if ($n/isGroup eq "true") then 1 else 0
        let $wc := dutil:num-of-spoken-words($doc//tei:body, $id)
        return
          <node xmlns="http://www.gexf.net/1.2draft"
            id="{$id}" label="{$label}">
            <attvalues>
              <attvalue for="person-group" value="{$group}" />
              <attvalue for="number-of-words" value="{$wc}" />
            {
              if ($sex) then
                <attvalue for="gender" value="{$sex}"></attvalue>
              else ()
            }
            </attvalues>
          </node>

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
            <attributes class="node" mode="static">
              <attribute id="gender" title="Gender" type="string"/>
              <attribute id="person-group" title="Person group" type="boolean"/>
              <attribute id="number-of-words" title="Number of spoken words" type="integer"/>
            </attributes>
            <nodes>{$nodes}</nodes>
            <edges>{$edges}</edges>
          </graph>
        </gexf>
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/segmentation")
  %rest:produces("application/xml", "text/xml")
  %output:media-type("text/xml")
function api:segmentation($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
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

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/spoken-text")
  %rest:query-param("gender", "{$gender}")
  %rest:produces("text/plain")
  %output:media-type("text/plain")
function api:spoken-text($corpusname, $playname, $gender) {
  let $doc := dutil:get-doc($corpusname, $playname)
  let $genders := tokenize($gender, ',')
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else if (
      $gender and
      $genders[.!="MALE" and .!="FEMALE" and .!="UNKNOWN"]
    ) then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        "gender must be ""FEMALE"", ""MALE"", or ""UNKNOWN"""
      )
    else
      let $sp := if ($gender) then
        dutil:get-speech-by-gender($doc//tei:body, $genders)
      else
        dutil:get-speech($doc//tei:body, ())
      let $txt := string-join($sp/normalize-space(), '&#10;')
      return $txt
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/stage-directions")
  %rest:produces("text/plain")
  %output:media-type("text/plain")
function api:stage-directions($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $stage := $doc//tei:body//tei:stage
      let $txt := string-join($stage/normalize-space(), '&#10;')
      (: let $txt := "FOO" :)
      return $txt
};

declare 
    %rest:POST
    %rest:path("/rdf")
    %rest:produces("application/rdf+xml")
    %output:media-type("application/rdf+xml")
function api:generateRDF() {
    (:~ Generates an RDF-Dump of the data; stores file in $rdf-collection
    @author Ingo Börner
    @returns 
    :)
    let $rdf-collection := "/db/data/dracor/rdf"
    let $rdf-filename := "dracor-data.xml"
    
    let $collection := ""
    let $filename := ""
    
    let $plays := collection($config:data-root)//tei:TEI

    let $inner :=
        for $play in $plays 
        let $collection-id := (replace($play/base-uri(),$config:data-root,'') => tokenize("/"))[2]
        let $play-uri := 'https://dracor.org/' || $collection-id || "/" || ($play/base-uri() => tokenize("/"))[last()] => substring-before('.xml')
        let $wikidata := "http://www.wikidata.org/entity/" || $play//tei:publicationStmt//tei:idno[@type='wikidata']/text()
        let $label := ($play//tei:fileDesc/tei:titleStmt//tei:author/text() => string-join(' ')) || ": " || ($play//tei:fileDesc/tei:titleStmt//tei:title/text() => string-join(' '))
        let $dracor-collection := "https://dracor.org/" || $collection-id 
        
    return
        
        <rdf:Description rdf:about="{$play-uri}">
            <owl:sameAs rdf:resource="{$wikidata}"/>
            <rdfs:label>{$label}</rdfs:label>
            <dracon:collection rdf:resource="{$dracor-collection}"/>
        </rdf:Description>

    let $rdf-data :=  <rdf:RDF 
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" 
    xmlns:owl="http://www.w3.org/2002/07/owl#" 
    xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
    xmlns:dracon="http://dracor.org/ontology#"
    >
         {$inner}
             
         </rdf:RDF>
    return
        ($rdf-data,
        xmldb:store($rdf-collection, $rdf-filename, $rdf-data)
        )
    
    
};

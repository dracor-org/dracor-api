xquery version "3.1";

module namespace api = "http://dracor.org/ns/exist/api";

import module namespace config = "http://dracor.org/ns/exist/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";
import module namespace load = "http://dracor.org/ns/exist/load" at "load.xqm";
import module namespace sparql = "http://exist-db.org/xquery/sparql"
  at "java:org.exist.xquery.modules.rdf.SparqlModule";

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

declare function local:get-corpus-metrics-xml ($corpus as xs:string) {
  let $collection-uri := concat($config:data-root, "/", $corpus)
  let $col := collection($collection-uri)
  let $metrics-uri := concat($config:metrics-root, "/", $corpus)
  let $metrics := collection($metrics-uri)
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
      <text>{sum($metrics//text)}</text>
      <sp>{sum($metrics//sp)}</sp>
      <stage>{sum($metrics//stage)}</stage>
    </wordcount>
    <updated>{max($metrics//metrics/xs:dateTime(@updated))}</updated>
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
          for $corpus in collection($config:data-root)/corpus
          return
          <metrics>
            <corpus>{$corpus/title, $corpus/name}</corpus>
            {
              for $m in local:get-corpus-metrics-xml($corpus/name/text())/*
              return $m
            }
          </metrics>
        }
      </json>
};

declare function local:get-corpus-metrics ($corpus as xs:string) {
  let $collection-uri := concat($config:data-root, "/", $corpus)
  let $col := collection($collection-uri)
  let $metrics-uri := concat($config:metrics-root, "/", $corpus)
  let $metrics := collection($metrics-uri)
  let $num-plays := count($col/tei:TEI)
  let $num-characters := count($col//tei:listPerson/tei:person)
  let $num-male := count($col//tei:listPerson/tei:person[@sex="MALE"])
  let $num-female := count($col//tei:listPerson/tei:person[@sex="FEMALE"])
  let $num-text := count($col//tei:text)
  let $num-stage := count($col//tei:stage)
  let $num-sp := count($col//tei:sp)
  return map {
    "plays": $num-plays,
    "characters": $num-characters,
    "male": $num-male,
    "female": $num-female,
    "text": $num-text,
    "sp": $num-sp,
    "stage": $num-stage,
    "wordcount": map {
      "text": sum($metrics//text),
      "sp": sum($metrics//sp),
      "stage": sum($metrics//stage)
    },
    "updated": max($metrics//metrics/xs:dateTime(@updated))
  }
};

declare
  %rest:GET
  %rest:path("/corpora")
  %rest:query-param("include", "{$include}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora($include) {
  array {
    for $corpus in collection($config:data-root)/corpus
    let $name := $corpus/name/text()
    order by $name
    return map:new ((
      map:entry("name", $name),
      map:entry("title", $corpus/title/text()),
      map:entry("uri", $config:api-base || '/corpora/' || $name),
      if ($corpus/repository) then (
        map:entry("repository", $corpus/repository/text())
      ) else (),
      if ($include = "metrics") then (
        map:entry("metrics", local:get-corpus-metrics($name))
      ) else ()

    ))
  }
};

declare
  %rest:PUT("{$data}")
  %rest:path("/corpora")
  %rest:consumes("application/json")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora-put($data) {
  let $json := parse-json(util:base64-decode($data))
  let $name := $json?name

  return if (collection($config:data-root)/corpus[name = $name]) then
    (
      <rest:response>
        <http:response status="409"/>
      </rest:response>,
      map {
        "error": "corpus already exists"
      }
    )
  else if (not($name) or not($json?title)) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "missing name or title"
      }
    )
  else if (not(matches($name, '^[-a-z0-1]+$'))) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "invalid name",
        "message": "Only lower case ASCII letters and digits are accepted."
      }
    )
  else
    let $corpus :=
      <corpus>
        <name>{$name}</name>
        <title>{$json?title}</title>
        {
          if ($json?repository)
          then <repository>{$json?repository}</repository>
          else ()
        }
        {if ($json?archive) then <archive>{$json?archive}</archive> else ()}
      </corpus>
    return (
      util:log-system-out("creating corpus"),
      util:log-system-out($corpus),
      xmldb:create-collection($config:data-root, $name),
      xmldb:create-collection($config:metrics-root, $name),
      xmldb:create-collection($config:rdf-root, $name),
      xmldb:store($config:data-root, $name || ".xml", $corpus),
      $json
    )
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:index($corpusname) {
  let $corpus := collection($config:data-root)/corpus[name=$corpusname]
  let $title := $corpus/title/text()
  let $collection := concat($config:data-root, "/", $corpusname)
  let $col := collection($collection)
  return
    if (not(xmldb:collection-available($collection))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      <index>
        <name>{$corpusname}</name>
        <title>{$title}</title>
        {if ($corpus/repository) then $corpus/repository else ()}
        {
          for $tei in $col//tei:TEI
          let $filename := tokenize(base-uri($tei), "/")[last()]
          let $id := tokenize($filename, "\.")[1]
          let $subtitle := $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
          let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
          let $authors := $tei//tei:fileDesc/tei:titleStmt/tei:author
          let $play-uri :=
            $config:api-base || "/corpora/" || $corpusname || "/play/" || $id
          let $metrics-url :=
            $config:metrics-root || "/" || $corpusname || "/" || $filename
          let $network-size := doc($metrics-url)//network/size/text()
          let $yearNormalized := dutil:get-normalized-year($tei)
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
              <yearNormalized>{$yearNormalized}</yearNormalized>
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
  %rest:DELETE
  %rest:path("/corpora/{$corpusname}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:index($corpusname, $auth) {
  if (not($auth)) then
    (
      <rest:response>
        <http:response status="401"/>
      </rest:response>,
      map {
        "message": "authorization required"
      }
    )
  else

  let $corpus := collection($config:data-root)/corpus[name = $corpusname]

  return
    if (not($corpus)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $url := $config:data-root || "/" || $corpusname || ".xml"
      return
        if ($url = $corpus/base-uri()) then
        (
          xmldb:remove($config:data-root, $corpusname || ".xml"),
          xmldb:remove($config:data-root || "/" || $corpusname),
          xmldb:remove($config:metrics-root || "/" || $corpusname),
          xmldb:remove($config:rdf-root || "/" || $corpusname),
          map {
            "message": "corpus deleted",
            "uri": $url
          }
        )
        else
        (
          <rest:response>
            <http:response status="404"/>
          </rest:response>
        )
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/metadata")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpus-meta-data($corpusname) {
  let $meta := dutil:get-corpus-meta-data($corpusname)
  return $meta
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/metadata")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:corpus-meta-data-csv($corpusname) {
  let $meta := dutil:get-corpus-meta-data($corpusname)
  (: make sure 'year' and 'name' are first :)
  let $columns := (
    "name", "yearNormalized",
    map:keys($meta[1])[.!="name" and .!="yearNormalized" and .!="playName"]
  )
  let $header := concat(string-join($columns, ","), "&#10;")
  let $rows :=
    for $m in $meta return concat(
      string-join((
        for $c in $columns return if (count($m($c)) = 0) then '' else $m($c)
      ), ','), "&#10;")
  return ($header, $rows)
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/metadata.csv")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:corpus-meta-data-dotcsv($corpusname) {
  let $meta := dutil:corpus-meta-data($corpusname)
  let $header := concat(string-join($meta[1]/*/name(), ','), "&#10;")
  let $data := for $row in $meta
    return concat(string-join($row/*/string(), ','), "&#10;")
  return ($header, $data)
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/load")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:load-corpus($corpusname) {
  let $corpus := collection($config:data-root)/corpus[name = $corpusname]
  return
    if ($corpus) then
      array {load:load-corpus($corpus)}
    else
      (
        <rest:response><http:response status="404"/></rest:response>,
        map {"message": "no such corpus"}
      )
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
  %rest:PUT("{$data}")
  %rest:path("/corpora/{$corpusname}/play/{$playname}/tei")
  %rest:header-param("Authorization", "{$auth}")
  %rest:consumes("application/xml", "text/xml")
  %output:method("xml")
function api:play-tei-put($corpusname, $playname, $data, $auth) {
  if (not($auth)) then
    <rest:response>
      <http:response status="401"/>
    </rest:response>
  else

  let $corpus := collection($config:data-root)/corpus[name = $corpusname]
  let $doc := dutil:get-doc($corpusname, $playname)

  return
    if (not($corpus)) then
      (
        <rest:response>
          <http:response status="404"/>
        </rest:response>,
        <message>No such corpus</message>
      )
    else if (
      not($doc) and
      not(matches($playname, "^[a-z0-9]+([-a-z0-9]?[a-z0-9])?$"))
    )
    then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        <message>Unacceptable play name '{$playname}'. Use lower case ASCII characters, digits and dashes only.</message>
      )
    else if (not($data/tei:TEI)) then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        <message>TEI document required</message>
      )
    else
      let $filename := $playname || ".xml"
      let $collection := $config:data-root || "/" || $corpusname
      let $result := xmldb:store($collection, $filename, $data/tei:TEI)
      return $data
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/rdf")
  %rest:produces("application/xml", "text/xml")
  %output:media-type("application/xml")
function api:play-rdf($corpusname, $playname) {
  let $url := $config:rdf-root || "/" || $corpusname || "/" || $playname
    || ".rdf.xml"
  let $doc := doc($url)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else $doc
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

declare function local:get-text-by-character ($doc) {
  let $characters := dutil:distinct-speakers($doc//tei:body)
  return array {
    for $id in $characters
    let $label := $doc//tei:particDesc//(
      tei:person[@xml:id=$id]/tei:persName[1] |
      tei:personGrp[@xml:id=$id]/tei:name[1] |
      tei:persName[@xml:id=$id]
    )
    let $gender := $label/parent::*/@sex/string()
    let $isGroup := if ($label/parent::tei:personGrp)
    then true() else false()
    let $sp := dutil:get-speech($doc//tei:body, $id)
    return map {
      "id": $id,
      "label": $label/text(),
      "isGroup": $isGroup,
      "gender": $gender,
      "text": array {for $l in $sp return $l/normalize-space()}
    }
  }
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/spoken-text-by-character")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:spoken-text-by-character($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      local:get-text-by-character($doc)
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/spoken-text-by-character")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:spoken-text-by-character-csv($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $texts := local:get-text-by-character($doc)
      return (
        "ID,Label,Type,Gender,Text&#10;",
        for $t in $texts?*
        let $type := if ($t?isGroup) then "personGrp" else "person"
        let $text := string-join($t?text?*, '&#10;')
        return $t?id || ',"' || dutil:csv-escape($t?label) || '","' ||
          $type  || '","' || $t?gender || '","' ||
          dutil:csv-escape($text) || '"&#10;'
      )
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
      return $txt
};

(:~
 : SPARQL endpoint
 :)
declare
  %rest:GET
  %rest:path("/sparql")
  %rest:query-param("query", "{$query}")
  %rest:produces("application/sparql-results+xml", "application/xml")
  %output:media-type("application/sparql-results+xml")
  %output:method("xml")
function api:sparql-get($query as xs:string*) {
  try {
    if ($query) then
      sparql:query($query)
    else (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      <error>
        <message>missing 'query' parameter</message>
      </error>
    )
  } catch * {
    <rest:response>
      <http:response status="400"/>
    </rest:response>,
    <error>
      <message>SPARQL execution failed</message>
      <code>{$err:code}</code>
      <query>{$query}</query>
    </error>
  }
};

declare
  %rest:POST("{$query}")
  %rest:path("/sparql")
  %rest:header-param("Content-Type", "{$type}")
  %rest:consumes("application/sparql-query")
  %rest:produces("application/sparql-results+xml", "application/xml")
  %output:media-type("application/sparql-results+xml")
  %output:method("xml")
function api:sparql-post($query as xs:string*, $type) {
  try {
    if ($query) then
      sparql:query($query)
    else (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      <error>
        <message>missing query</message>
      </error>
    )
  } catch * {
    <rest:response>
      <http:response status="400"/>
    </rest:response>,
    <error>
      <message>SPARQL execution failed</message>
      <code>{$err:code}</code>
      <query>{$query}</query>
    </error>
  }
};

(:
 : CAVEAT: this only seems to work if the Content-Type is exactly
 : "application/x-www-form-urlencoded". If the header specifies a charset like
 : "application/x-www-form-urlencoded; charset=UTF-8" $query will not get
 : populated.
 :)
declare
  %rest:POST
  %rest:path("/sparql")
  %rest:form-param("query","{$query}")
  %rest:header-param("Content-Type", "{$type}")
  %rest:consumes("application/x-www-form-urlencoded")
  %rest:produces("application/sparql-results+xml", "application/xml")
  %output:media-type("application/sparql-results+xml")
  %output:method("xml")
function api:sparql-post-form($query as xs:string*, $type) {
  try {
    if ($query) then
      sparql:query($query)
    else (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      <error>
        <message>missing 'query' parameter</message>
      </error>
    )
  } catch * {
    <rest:response>
      <http:response status="400"/>
    </rest:response>,
    <error>
      <message>SPARQL execution failed</message>
      <code>{$err:code}</code>
      <query>{$query}</query>
    </error>
  }
};

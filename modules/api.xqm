xquery version "3.1";

module namespace api = "http://dracor.org/ns/exist/api";

import module namespace config = "http://dracor.org/ns/exist/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";
import module namespace load = "http://dracor.org/ns/exist/load" at "load.xqm";
import module namespace openapi = "https://lab.sub.uni-goettingen.de/restxqopenapi";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace repo = "http://exist-db.org/xquery/repo";
declare namespace expath = "http://expath.org/ns/pkg";
declare namespace json = "http://www.w3.org/2013/XSL/json";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace jsn = "http://www.json.org";
declare namespace test = "http://exist-db.org/xquery/xqsuite";
declare namespace rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#";

declare variable $api:metadata-columns := (
  "name",
  "id",
  "firstAuthor",
  "numOfCoAuthors",
  "yearNormalized",
  "size",
  "genre",
  "libretto",
  "averageClustering",
  "density",
  "averagePathLength",
  "maxDegreeIds",
  "averageDegree",
  "diameter",
  "yearPremiered",
  "yearPrinted",
  "maxDegree",
  "numOfSpeakers",
  "numOfSpeakersFemale",
  "numOfSpeakersMale",
  "numOfSpeakersUnknown",
  "numPersonGroups",
  "numConnectedComponents",
  "yearWritten",
  "numOfSegments",
  "wikipediaLinkCount",
  "numOfActs",
  "wordCountText",
  "wordCountSp",
  "wordCountStage"
);

(:~
 : API info
 :
 : Shows version numbers of the dracor-api app and the underlying eXist-db.
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/info")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:info() {
  let $expath := config:expath-descriptor()
  let $repo := config:repo-descriptor()
  return map {
    "name": $expath/expath:title/string(),
    "version": $expath/@version/string(),
    "status": $repo/repo:status/string(),
    "existdb": system:get-version()
  }
};

(:~
 : OpenAPI info
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/openapi")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:openapi() {
  openapi:main("/db/apps/dracor")
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

declare function local:id-to-url ($id, $accept) {
  let $base := "https://dracor.org/"
  let $idno := collection($config:data-root)//tei:publicationStmt
    /tei:idno[@type="dracor" and .= $id]
  let $parts := tokenize(base-uri($idno/parent::*), "[/.]")
  let $corpusname := $parts[last()-2]
  let $playname := $parts[last()-1]

  return if ($idno) then
    if ($accept = "application/rdf+xml") then
      $base || "api/corpora/" || $corpusname || "/play/" || $playname || "/rdf"
    else if ($accept = "application/json") then
      $base || "api/corpora/" || $corpusname || "/play/" || $playname
    else
      $base || $corpusname || "/" || $playname
  else ()
};

(:~
 : Resolve DraCor ID of a play
 :
 : Depending on the `Accept` header this endpoint redirects to either the RDF
 : representation, the JSON metadata or the dracor.org page of the play
 : identified by $id.
 :
 : @param $id DraCor ID
 : @param $accept Accept header value
 : @result redirect
 :)
declare
  %rest:GET
  %rest:path("/id/{$id}")
  %rest:header-param("Accept", "{$accept}")
function api:id-to-url($id, $accept) {
  let $url := local:id-to-url($id, $accept)
  return if (not($url)) then
    <rest:response>
      <http:response status="404"/>
    </rest:response>
  else
    <rest:response>
      <http:response status="303">
        <http:header name="location" value="{$url}"/>
      </http:response>
    </rest:response>
};

declare function local:get-corpus-metrics ($corpus as xs:string) {
  let $collection-uri := concat($config:data-root, "/", $corpus)
  let $col := collection($collection-uri)
  let $metrics-uri := concat($config:metrics-root, "/", $corpus)
  let $metrics := collection($metrics-uri)
  let $num-plays := count($col/tei:TEI)
  let $list := $col//tei:particDesc/tei:listPerson
  let $num-characters := count($list/(tei:person|tei:personGrp))
  let $num-male := count($list/(tei:person|tei:personGrp)[@sex="MALE"])
  let $num-female := count($list/(tei:person|tei:personGrp)[@sex="FEMALE"])
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

(:~
 : List available corpora
 :
 : @result JSON array of objects
 :)
declare
  %rest:GET
  %rest:path("/corpora")
  %rest:query-param("include", "{$include}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora($include) {
  array {
    for $corpus in collection($config:data-root)//tei:teiCorpus
    let $info := dutil:get-corpus-info($corpus)
    let $name := $info?name
    order by $name
    return map:merge ((
      $info,
      map:entry("uri", $config:api-base || '/corpora/' || $name),
      if ($include = "metrics") then (
        map:entry("metrics", local:get-corpus-metrics($name))
      ) else ()

    ))
  }
};

(:~
 : Add new corpus
 :
 : @param $data corpus.xml containing teiCorpus element.
 : @result XML document
 :)
declare
  %rest:POST("{$data}")
  %rest:path("/corpora")
  %rest:header-param("Authorization", "{$auth}")
  %rest:consumes("application/xml", "text/xml")
  %rest:produces("application/json")
  %output:method("json")
function api:corpora-post-tei($data, $auth) {
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

  let $header := $data//tei:teiCorpus/tei:teiHeader
  let $name := $header//tei:publicationStmt/tei:idno[
    @type = "URI" and @xml:base = "https://dracor.org/"
  ]/text()

  let $title := $header//tei:titleStmt/tei:title[1]/text()

  return if (not($header)) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {
        "error": "invalid document, expecting <teiCorpus>"
      }
    )
  else if (not($name) or not($title)) then
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
    let $corpus := dutil:get-corpus($name)
    return if ($corpus) then (
      <rest:response>
        <http:response status="409"/>
      </rest:response>,
      map {
        "error": "corpus already exists"
      }
    ) else (
      let $tei-dir := concat($config:data-root, '/', $name)
      return (
        util:log-system-out("creating corpus"),
        util:log-system-out($data),
        xmldb:create-collection($config:data-root, $name),
        xmldb:create-collection($config:metrics-root, $name),
        xmldb:create-collection($config:rdf-root, $name),
        xmldb:store($tei-dir, "corpus.xml", $data),
        map {
          "name": $name,
          "title": $title
        }
      )
    )
};

(:~
 : Add new corpus
 :
 : @param $data JSON object describing corpus meta data
 : @result JSON object
 :)
declare
  %rest:POST("{$data}")
  %rest:path("/corpora")
  %rest:consumes("application/json")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora-post-json($data) {
  let $json := parse-json(util:base64-decode($data))
  let $name := $json?name
  let $description := $json?description
  let $corpus := dutil:get-corpus($name)

  return if ($corpus) then
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
      <teiCorpus xmlns="http://www.tei-c.org/ns/1.0">
        <teiHeader>
          <fileDesc>
            <titleStmt>
              <title>{$json?title}</title>
            </titleStmt>
            <publicationStmt>
              <idno type="URI" xml:base="https://dracor.org/">{$name}</idno>
              {
                if ($json?repository)
                then <idno type="repo">{$json?repository}</idno>
                else ()
              }
            </publicationStmt>
          </fileDesc>
          {if ($json?description) then (
            <encodingDesc>
              <projectDesc>
                {
                  for $p in tokenize($json?description, "&#10;&#10;")
                  return <p>{$p}</p>
                }
              </projectDesc>
            </encodingDesc>
          ) else ()}
        </teiHeader>
      </teiCorpus>
    let $tei-dir := concat($config:data-root, '/', $name)
    return (
      util:log-system-out("creating corpus"),
      util:log-system-out($corpus),
      xmldb:create-collection($config:data-root, $name),
      xmldb:create-collection($config:metrics-root, $name),
      xmldb:create-collection($config:rdf-root, $name),
      xmldb:store($tei-dir, "corpus.xml", $corpus),
      $json
    )
};

(:~
 : List corpus content
 :
 : Lists all plays available in the corpus including the id, title, author(s)
 : and other meta data.
 :
 : @param $corpusname
 : @result
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:index($corpusname) {
  let $corpus := dutil:get-corpus-info-by-name($corpusname)
  let $title := $corpus?title
  let $description := $corpus?description
  let $collection := concat($config:data-root, "/", $corpusname)
  let $col := collection($collection)
  return
    if (not($corpus?name) or not(xmldb:collection-available($collection))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      <index>
        <name>{$corpus?name}</name>
        <title>{$corpus?title}</title>
        {
          if ($corpus?repository)
          then <repository>{$corpus?repository}</repository>
          else ()
        }
        {
          if ($corpus?description)
          then <description>{$corpus?description}</description>
          else ()
        }
        {
          if ($corpus?licence)
          then <licence>{$corpus?licence}</licence>
          else ()
        }
        {
          if ($corpus?licenceUrl)
          then <licenceUrl>{$corpus?licenceUrl}</licenceUrl>
          else ()
        }
        {
          for $tei in $col//tei:TEI
          let $filename := tokenize(base-uri($tei), "/")[last()]
          let $name := tokenize($filename, "\.")[1]
          let $id := dutil:get-dracor-id($tei)
          let $subtitle := $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
          let $years := dutil:get-years-iso($tei)
          let $authors := dutil:get-authors($tei)
          let $play-uri :=
            $config:api-base || "/corpora/" || $corpusname || "/play/" || $name
          let $metrics-url :=
            $config:metrics-root || "/" || $corpusname || "/" || $filename
          let $network-size := doc($metrics-url)//network/size/text()
          let $yearNormalized := dutil:get-normalized-year($tei)
          order by $authors[1]?name
          return
            <dramas json:array="true">
              <id>{$id}</id>
              <name>{$name}</name>
              <title>
                {$tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space() }
              </title>
              {if ($subtitle) then <subtitle>{$subtitle}</subtitle> else ''}
              <author key="{$authors[1]?key}">
                <name>{$authors[1]?name}</name>
              </author>
              {
                for $author in $authors
                return
                  <authors json:array="true">
                    <name>{$author?name}</name>
                    <fullname>{$author?fullname}</fullname>
                    <shortname>{$author?shortname}</shortname>
                    {if ($author?key != "") then <key>{$author?key}</key> else ()}
                    {
                      for $name in $author?alsoKnownAs?*
                      return <alsoKnownAs json:array="true">{$name}</alsoKnownAs>
                    }
                  </authors>
              }
              <yearNormalized>{$yearNormalized}</yearNormalized>
              <source>
                {$tei//tei:sourceDesc/tei:bibl[@type="digitalSource"]/tei:name/string()}
              </source>
              <sourceUrl>
                {
                  $tei//tei:sourceDesc/tei:bibl[@type="digitalSource"]
                    /tei:idno[@type="URL"][1]/string()
                }
              </sourceUrl>
              <printYear>{$years?print}</printYear>
              <premiereYear>{$years?premiere}</premiereYear>
              <writtenYear>{$years?written}</writtenYear>
              <networkSize>{$network-size}</networkSize>
              <networkdataCsvUrl>{$play-uri}/networkdata/csv</networkdataCsvUrl>
              <wikidataId>
                {$tei//tei:publicationStmt/tei:idno[@type="wikidata"]/string()}
              </wikidataId>
            </dramas>
        }
      </index>
};

(:~
 : Load corpus data from its repository
 :
 : Posting `{"load": true}` to the corpus URI reloads the data for this corpus
 : from its repository (if defined). This endpoint requires authorization.
 :
 : @param $corpusname Corpus name
 : @param $data JSON object
 : @param $auth Authorization header value
 : @result JSON object
 :)
declare
  %rest:POST("{$data}")
  %rest:path("/corpora/{$corpusname}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:consumes("application/json")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
  %test:arg("corpusname", "test")
  %test:arg("data", '{"load": true}')
  %test:arg("auth", "Basic YWRtaW46")
function api:post-corpus($corpusname, $data, $auth) {
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

  let $json := parse-json(util:base64-decode($data))
  let $corpus := dutil:get-corpus-info-by-name($corpusname)

  return
    if (not($corpus?name)) then
      (
        <rest:response><http:response status="404"/></rest:response>,
        map {"message": "no such corpus"}
      )
    else if (count($json) = 0) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "missing payload"}
      )
    else if ($json?load) then
      let $job-name := "load-corpus-" || $corpusname
      let $params := (
        <parameters>
          <param name="corpusname" value="{$corpusname}"/>
        </parameters>
      )

      (: delete completed job before scheduling new one :)
      (: NB: usually this seems to happen automatically but apparently we
       : cannot rely on it. :)
      let $jobs := scheduler:get-scheduled-jobs()
      let $complete := $jobs//scheduler:job
        [@name=$job-name and scheduler:trigger/state = 'COMPLETE']
      let $log := if ($complete) then (
        util:log("info", "deleting completed job"),
        scheduler:delete-scheduled-job($job-name)
      ) else ()

      let $result := scheduler:schedule-xquery-periodic-job(
        "/db/apps/dracor/jobs/load-corpus.xq",
        1, $job-name, $params, 0, 0
      )

      return if ($result) then
        (
          <rest:response><http:response status="202"/></rest:response>,
          map {"message": "corpus update scheduled"}
        )
      else
        (
          <rest:response><http:response status="409"/></rest:response>,
          map {"message": "cannot schedule update"}
        )
    else
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "invalid payload"}
      )
};

(:~
 : Remove corpus from database
 :
 : @param $corpusname Corpus name
 : @param $auth Authorization header value
 : @result JSON object
 :)
declare
  %rest:DELETE
  %rest:path("/corpora/{$corpusname}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:delete-corpus($corpusname, $auth) {
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

  let $corpus := dutil:get-corpus($corpusname)

  return
    if (not($corpus)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $url := $config:data-root || "/" || $corpusname || "/corpus.xml"
      return
        if ($url = $corpus/base-uri()) then
        (
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

(:~
 : List of metadata for all plays in a corpus
 :
 : @param $corpusname Corpus name
 : @result JSON array of metadata for all plays
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/metadata")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpus-meta-data($corpusname) {
  let $corpus := dutil:get-corpus($corpusname)
  return
    if (not($corpus)) then
      (
        <rest:response><http:response status="404"/></rest:response>,
        map {"message": "no such corpus"}
      )
    else
      let $meta := dutil:get-corpus-meta-data($corpusname)
      return $meta
};

declare function api:get-corpus-meta-data-csv($corpusname) {
  let $corpus := dutil:get-corpus($corpusname)
  return
    if (not($corpus)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $meta := dutil:get-corpus-meta-data($corpusname)
      let $header := concat(string-join($api:metadata-columns, ","), "&#10;")
      let $rows :=
        for $m in $meta return concat(
          '"',
          string-join((
            for $c in $api:metadata-columns
            return if (count($m($c)) = 0) then '' else dutil:csv-escape($m($c))
          ), '","'), '"&#10;')
      return ($header, $rows)
};

(:~
 : List of metadata for all plays in a corpus
 :
 : @param $corpusname Corpus name
 : @result comma separated list of metadata for all plays
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/metadata")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:corpus-meta-data-csv($corpusname) {
  api:get-corpus-meta-data-csv($corpusname)
};

(:~
 : List of metadata for all plays in a corpus
 :
 : This endpoint is deprecated. Please use `/corpora/{corpusname}/metadata`
 : with an appropriate `Accept` header instead.
 :
 : @param $corpusname Corpus name
 : @result comma separated list of metadata for all plays
 : @deprecated
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/metadata.csv")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:corpus-meta-data-dotcsv($corpusname) {
  api:get-corpus-meta-data-csv($corpusname)
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

(:~
 : Get metadata for a single play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result JSON object with play meta data
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:play-info($corpusname, $playname) {
  let $info := dutil:get-play-info($corpusname, $playname)
  return
    if (count($info)) then
      $info
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

(:~
 : Remove a single play from the corpus
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @param $auth Authorization header value
 : @result JSON object
 :)
declare
  %rest:DELETE
  %rest:path("/corpora/{$corpusname}/play/{$playname}")
  %rest:header-param("Authorization", "{$auth}")
  %output:method("json")
function api:play-delete($corpusname, $playname, $data, $auth) {
  if (not($auth)) then
    <rest:response>
      <http:response status="401"/>
    </rest:response>
  else

  let $doc := dutil:get-doc($corpusname, $playname)

  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $filename := $playname || ".xml"
      let $collection := $config:data-root || "/" || $corpusname
      return (xmldb:remove($collection, $filename))
};

(:~
 : Get metrics for a single play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result JSON object with play metrics
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/metrics")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:play-metrics($corpusname, $playname) {
  let $metrics := dutil:get-play-metrics($corpusname, $playname)
  return
    if (count($metrics)) then
      $metrics
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

(:~
 : Get TEI representation of a single play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result TEI document
 :)
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
      let $model-pi := $doc/processing-instruction(xml-model)
      return if ($model-pi) then
        document {
          processing-instruction {'xml-model'} {$model-pi/string()},
          $tei
        }
      else $tei
};

(:~
 : Add new or update existing TEI document
 :
 : When sending a PUT request to a new play URI, the request body is stored in
 : the database as a new document accessible under that URI. If the URI already
 : exists the corresponding TEI document is updated with the request body.
 :
 : The `playname` parameter of a new URI must consist of lower case ASCII
 : characters, digits and/or dashes only.
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @param $data TEI document
 : @param $auth Authorization header value
 : @result updated TEI document
 :)
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

  let $corpus := dutil:get-corpus($corpusname)
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
      not(matches($playname, "^[a-z0-9]+(-?[a-z0-9]+)*$"))
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

(:~
 : Get RDF document for a single play
 :
 : @param
 : @result
 :)
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

(:~
 : Get network data of a play as CSV
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result CSV document
 :)
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
            for $seg in dutil:get-segments($doc//tei:TEI)
            return
              <sgm>
                {
                  for $id in dutil:distinct-speakers($seg)
                  return <spkr>{$id}</spkr>
                }
              </sgm>
          }
        </segments>

      let $links := map:merge(
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

      return string-join(("Source,Type,Target,Weight", $rows, ""), "&#10;")
};

declare function local:make-gexf-nodes($cast, $doc) as element()* {
  for $n in $cast?*
  let $id := $n?id
  let $label := $n?name
  let $sex := $n?sex
  let $group := if ($n?isGroup) then 1 else 0
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
};

(:~
 : Get network data of a play as GEXF
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result GEXF document
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/networkdata/gexf")
  %output:method("xml")
  %output:omit-xml-declaration("no")
function api:networkdata-gexf($corpusname, $playname) {
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
            for $seg in dutil:get-segments($doc//tei:TEI)
            return
              <sgm>
                {
                  for $id in dutil:distinct-speakers($seg)
                  return <spkr>{$id}</spkr>
                }
              </sgm>
          }
        </segments>

      let $info := dutil:get-play-info($corpusname, $playname)
      let $authors := string-join($info?authors?*?name, ' · ')
      let $title := $info?title

      let $links := map:merge(
        for $spkr in $cast
        let $cooccurences := $segments//sgm[spkr=$spkr]/spkr/text()
        return map:entry($spkr, distinct-values($cooccurences)[.!=$spkr])
      )

      let $nodes := local:make-gexf-nodes($info?cast, $doc)

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

(:~
 : Get network data of a play as GraphML
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result GraphML document
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/networkdata/graphml")
  %output:method("xml")
  %output:omit-xml-declaration("no")
function api:networkdata-graphml($corpusname, $playname) {
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
            for $seg in dutil:get-segments($doc//tei:TEI)
            return
              <sgm>
                {
                  for $id in dutil:distinct-speakers($seg)
                  return <spkr>{$id}</spkr>
                }
              </sgm>
          }
        </segments>

      let $info := dutil:get-play-info($corpusname, $playname)

      let $links := map:merge(
        for $spkr in $cast
        let $cooccurences := $segments//sgm[spkr=$spkr]/spkr/text()
        return map:entry($spkr, distinct-values($cooccurences)[.!=$spkr])
      )

      let $edges :=
        for $spkr at $pos in $cast
          for $cooc in $links($spkr)
          where index-of($cast, $cooc)[1] gt $pos
          let $weight := $segments//sgm[spkr=$spkr][spkr=$cooc] => count()
          return
            <edge xmlns="http://graphml.graphdrawing.org/xmlns"
             id="{$spkr}|{$cooc}" source="{$spkr}" target="{$cooc}">
             <data key="weight">{$weight}</data>
           </edge>

      return
        <graphml xmlns="http://graphml.graphdrawing.org/xmlns">
          <key attr.name="label" attr.type="string" for="node" id="label"/>
          <key attr.name="Edge Label" attr.type="string" for="edge" id="edgelabel"/>
          <key attr.name="weight" attr.type="double" for="edge" id="weight"/>
          <key attr.name="Gender" attr.type="string" for="node" id="gender"/>
          <key attr.name="Person group" attr.type="boolean" for="node" id="person-group"/>
          <key attr.name="Number of spoken words" attr.type="int" for="node" id="number-of-words"/>
          <graph edgedefault="undirected">
            {
              for $n in $info?cast?*
              let $id := $n?id
              let $label := $n?name
              let $sex := $n?sex
              let $wc := dutil:num-of-spoken-words($doc//tei:body, $id)
              return
                <node id="{$id}" xmlns="http://graphml.graphdrawing.org/xmlns">
                  <data key="label">{$label}</data>
                  {if ($sex) then <data key="gender">{$sex}</data> else ()}
                  <data key="person-group">
                    {if ($n?isGroup) then "true" else "false"}
                  </data>
                  <data key="number-of-words">{$wc}</data>
                </node>
            }
            {$edges}
          </graph>
        </graphml>
};

(:~
 : Get relation data for a play as CSV
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result CSV document
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/relations/csv")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:relations-csv($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  let $info := dutil:get-play-info($corpusname, $playname)
  let $relations := dutil:get-relations($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else if (count($relations) = 0) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      let $rows :=
        for $rel in $relations
        return string-join((
          $rel?source,
          if ($rel?directed) then 'Directed' else 'Undirected',
          $rel?target,
          $rel?type
        ), ",")

      let $filename := $info?id || '-' || $info?name || '-relations.csv'

      return (
        <rest:response>
          <http:response status="200">
            <http:header
              name="Content-disposition"
              value="inline; filename={$filename}"
            />
          </http:response>
        </rest:response>,
        string-join(("Source,Type,Target,Label", $rows, ""), "&#10;")
      )
};

(:~
 : Get relation data for a play as GEXF
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result GEXF document
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/relations/gexf")
  %output:method("xml")
  %output:omit-xml-declaration("no")
function api:relations-gexf($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  let $info := dutil:get-play-info($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else if (count($info?relations?*) = 0) then
      (
        <rest:response>
          <http:response status="404"/>
        </rest:response>,
        <message>No relations available.</message>
      )
    else
      let $authors := string-join($info?authors?*?name, ' · ')
      let $title := $info?title

      let $nodes := local:make-gexf-nodes($info?cast, $doc)

      let $edges :=
        for $rel at $pos in $info?relations?*
          let $type := if ($rel?directed) then "directed" else "undirected"
          return
            <edge xmlns="http://www.gexf.net/1.2draft"
            id="{$pos}" source="{$rel?source}" target="{$rel?target}"
            type="{$type}" label="{$rel?type}"/>

      let $filename := $info?id || '-' || $info?name || '-relations.gexf'

      return (
        <rest:response>
          <http:response status="200">
            <http:header
              name="Content-disposition"
              value="inline; filename={$filename}"
            />
          </http:response>
        </rest:response>,
        <gexf xmlns="http://www.gexf.net/1.2draft" version="1.2">
          <meta>
            <creator>dracor.org</creator>
            <description>Relations for {$authors}: {$title}</description>
          </meta>
          <graph mode="static">
            <attributes class="node" mode="static">
              <attribute id="gender" title="Gender" type="string"/>
              <attribute id="person-group" title="Person group" type="boolean"/>
              <attribute id="number-of-words" title="Number of spoken words" type="integer"/>
            </attributes>
            <attributes class="edge" mode="static">
              <attribute id="label" title="Label" type="string"/>
            </attributes>
            <nodes>{$nodes}</nodes>
            <edges>{$edges}</edges>
          </graph>
        </gexf>
      )
};

(:~
 : Get relation data for a play as GraphML
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result GraphML document
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/relations/graphml")
  %output:method("xml")
  %output:omit-xml-declaration("no")
function api:relations-graphml($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  let $info := dutil:get-play-info($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else if (count($info?relations?*) = 0) then
      (
        <rest:response>
          <http:response status="404"/>
        </rest:response>,
        <message>No relations available.</message>
      )
    else
      let $edges :=
        for $rel at $pos in $info?relations?*
          let $directed := if ($rel?directed) then "true" else "false"
          return
            <edge
              xmlns="http://graphml.graphdrawing.org/xmlns"
              id="{$pos}"
              directed="{$directed}"
              source="{$rel?source}"
              target="{$rel?target}"
            >
              <data key="relation">{$rel?type}</data>
            </edge>

      let $filename := $info?id || '-' || $info?name || '-relations.graphml'

      return (
        <rest:response>
          <http:response status="200">
            <http:header
              name="Content-disposition"
              value="inline; filename={$filename}"
            />
          </http:response>
        </rest:response>,
        <graphml xmlns="http://graphml.graphdrawing.org/xmlns">
          <key attr.name="label" attr.type="string" for="node" id="label"/>
          <key attr.name="Relation" attr.type="string" for="edge" id="relation"/>
          <key attr.name="Gender" attr.type="string" for="node" id="gender"/>
          <key attr.name="Person group" attr.type="boolean" for="node" id="person-group"/>
          <graph edgedefault="undirected">
            {
              for $n in $info?cast?*
              let $id := $n?id
              let $label := $n?name
              let $sex := $n?sex
              return
                <node id="{$id}" xmlns="http://graphml.graphdrawing.org/xmlns">
                  <data key="label">{$label}</data>
                  {if ($sex) then <data key="gender">{$sex}</data> else ()}
                  <data key="person-group">
                    {if ($n?isGroup) then "true" else "false"}
                  </data>
                </node>
            }
            {$edges}
          </graph>
        </graphml>
      )
};

(:~
 : Get a list of characters of a play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result JSON array of objects representing character data
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/cast")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:cast-info($corpusname, $playname) {
  let $info := dutil:cast-info($corpusname, $playname)
  return
    if (count($info) > 0) then
      $info
    else
      <rest:response>
        <http:response status="404"/>
      </rest:response>
};

(:~
 : Get a list of characters of a play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result comma separated list of character data
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/cast")
  %rest:produces("text/csv")
  %output:media-type("text/csv")
  %output:method("text")
function api:cast-info-csv($corpusname, $playname) {
  let $info := dutil:cast-info($corpusname, $playname)
  let $keys := (
    "id", "name", "gender", "isGroup",
    "numOfScenes", "numOfSpeechActs", "numOfWords",
    "degree", "weightedDegree", "betweenness", "closeness", "eigenvector"
  )
  return if (count($info) = 0) then
    <rest:response>
      <http:response status="404"/>
    </rest:response>
  else (
    string-join($keys, ",") || "&#10;",
    for $c in $info?*
    let $row := for $key in $keys
      let $val := map:get($c, $key)
      return if (empty($val)) then ('') else ('"' || $val || '"')
    return string-join($row, ',') || '&#10;'
  )
};

declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/cast/csv")
  %output:media-type("text/csv")
  %output:method("text")
function api:cast-info-csv-ext($corpusname, $playname) {
  api:cast-info-csv($corpusname, $playname)
};

(:~
 : Get a list of segments and characters of a play
 :
 : This endpoint is deprecated. All the information is now available as JSON
 : from `/corpora/{corpusname}/play/{playname}`.
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result XML document
 : @deprecated
 :)
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

(:~
 : Get a list of segments and characters of a play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result list of comma separated segment data
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/segmentation")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:segmentation-csv($corpusname, $playname) {
  let $info := dutil:get-play-info($corpusname, $playname)
  return if (count($info) = 0) then
    <rest:response>
      <http:response status="404"/>
    </rest:response>
  else
  let $authors := string-join($info?authors?*?name, " | ")
  return (
    "segmentNumber,segmentTitle,castId,castName,gender,title,authors&#10;",
    for $seg in $info?segments?*
      for $id in $seg?speakers?*
      let $speaker := $info?cast?*[?id=$id]
      let $row := (
        $seg?number, $seg?title, $id, $speaker?name, $speaker?sex,
        $info?title, $authors
      ) ! dutil:csv-escape(.)
      return '"' || string-join($row, '","') || '"&#10;'
  )
};

(:~
 : Get spoken text of a play (excluding stage directions)
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @param $gender Gender ("MALE"|"FEMALE"|"UNKNOWN")
 : @param $relation Relation ("siblings"|"friends"|spouses"|"parent_of_active"|
 :   "parent_of_passive"|"lover_of_active"|"lover_of_passive"|
 :   "related_with_active"|"related_with_passive"|"associated_with_active"|
 :   "associated_with_passive")
 : @param $role Role
 : @result text
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/spoken-text")
  %rest:query-param("gender", "{$gender}")
  %rest:query-param("relation", "{$relation}")
  %rest:query-param("role", "{$role}")
  %rest:produces("text/plain")
  %output:media-type("text/plain")
function api:spoken-text($corpusname, $playname, $gender, $relation, $role) {
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
      let $sp := if ($gender or $relation or $role) then
        dutil:get-speech-filtered($doc//tei:body, $gender, $relation, $role)
      else
        dutil:get-speech($doc//tei:body, ())
      let $txt := string-join(($sp/normalize-space(), ""), '&#10;')
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
    let $role := $label/parent::*/@role/string()
    let $isGroup := if ($label/parent::tei:personGrp)
    then true() else false()
    let $sp := dutil:get-speech($doc//tei:body, $id)
    return map {
      "id": $id,
      "label": $label/text(),
      "isGroup": $isGroup,
      "gender": $gender,
      "roles": array {tokenize($role, '\s+')},
      "text": array {for $l in $sp return $l/normalize-space()}
    }
  }
};

declare function api:get-spoken-text-by-character($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      local:get-text-by-character($doc)
};

(:~
 : Get spoken text for each character of a play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result JSON object with texts per character
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/spoken-text-by-character")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:spoken-text-by-character($corpusname, $playname) {
  api:get-spoken-text-by-character($corpusname, $playname)
};

(:~
 : Get spoken text for each character of a play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result JSON object with texts per character
 :)
declare
  %rest:GET
  %rest:path(
    "/corpora/{$corpusname}/play/{$playname}/spoken-text-by-character.json"
  )
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:spoken-text-by-character-json($corpusname, $playname) {
  api:get-spoken-text-by-character($corpusname, $playname)
};

(:~
 : Get spoken text for each character of a play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result list of spoken text per character as CSV
 :)
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

(:~
 : Get all stage directions of a play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result text of all stage directions
 :)
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
 : Get all stage directions of a play including speakers
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result text of all stage directions
 :)
declare
  %rest:GET
  %rest:path("/corpora/{$corpusname}/play/{$playname}/stage-directions-with-speakers")
  %rest:produces("text/plain")
  %output:media-type("text/plain")
function api:stage-directions-with-speakers($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      for $stage in $doc//tei:body//tei:stage
      let $speaker := $stage/preceding-sibling::tei:speaker
      let $line := if ($speaker) then
        $speaker || "  " || normalize-space($stage)
      else normalize-space($stage)
      return $line || '&#10;'
};

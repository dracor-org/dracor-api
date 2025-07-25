xquery version "3.1";

module namespace api = "http://dracor.org/ns/exist/v1/api";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";
import module namespace load = "http://dracor.org/ns/exist/v1/load" at "load.xqm";
import module namespace wd = "http://dracor.org/ns/exist/v1/wikidata" at "wikidata.xqm";
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
  "wikidataId",
  "firstAuthor",
  "numOfCoAuthors",
  "title",
  "subtitle",
  "normalizedGenre",
  "digitalSource",
  "originalSourcePublisher",
  "originalSourcePubPlace",
  "originalSourceYear",
  "originalSourceNumberOfPages",
  "yearNormalized",
  "size",
  "libretto",
  "averageClustering",
  "density",
  "averagePathLength",
  "maxDegreeIds",
  "averageDegree",
  "diameter",
  "datePremiered",
  "yearPremiered",
  "yearPrinted",
  "maxDegree",
  "numOfSpeakers",
  "numOfSpeakersFemale",
  "numOfSpeakersMale",
  "numOfSpeakersUnknown",
  "numOfPersonGroups",
  "numConnectedComponents",
  "numEdges",
  "yearWritten",
  "numOfSegments",
  "wikipediaLinkCount",
  "numOfActs",
  "numOfScenes",
  "wordCountText",
  "wordCountSp",
  "wordCountStage",
  "numOfP",
  "numOfL"
);

(:~
 : API base
 :
 : Mirrors api:info
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/v1")
  %rest:produces("application/json")
  %output:method("json")
function api:base() {
  api:info()
};

(:~
 : API info
 :
 : Shows version numbers of the dracor-api app and the underlying eXist-db.
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/v1/info")
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
    "existdb": system:get-version(),
    "base": $config:api-base,
    "openapi": $config:api-base || "/openapi.yaml"
  }
};

(:~
 : OpenAPI info
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/v1/openapi")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:openapi() {
  openapi:main($config:app-root)
};

(:~
 : OpenAPI info yaml
 :
 : @result YAML
 :)
declare
  %rest:GET
  %rest:path("/v1/openapi.yaml")
  %rest:produces("application/yaml")
  %output:media-type("application/yaml")
  %output:method("text")
function api:openapi-yaml() {
  let $path := $config:app-root || "/api.yaml"
  let $expath := config:expath-descriptor()
  let $yaml := util:base64-decode(xs:string(util:binary-doc($path)))
  return replace(
    replace($yaml, 'https://dracor.org/api/v1', $config:api-base),
    'version: [0-9.]+',
    'version: ' || $expath/@version/string()
  )
};

declare
  %rest:GET
  %rest:path("/v1/resources")
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
  %rest:path("/v1/id/{$id}")
  %rest:header-param("Accept", "{$accept}")
function api:id-to-url($id, $accept) {
  let $url := dutil:id-to-url($id, $accept)
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
  let $collection-uri := concat($config:corpora-root, "/", $corpus)
  let $col := collection($collection-uri)
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
      "text": sum($col/metrics/text),
      "sp": sum($col/metrics/sp),
      "stage": sum($col/metrics/stage)
    },
    "updated": max($col/metrics/xs:dateTime(@updated))
  }
};

(:~
 : List available corpora
 :
 : @result JSON array of objects
 :)
declare
  %rest:GET
  %rest:path("/v1/corpora")
  %rest:query-param("include", "{$include}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpora($include) {
  array {
    for $corpus in collection($config:corpora-root)//tei:teiCorpus
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
 :
 : FIXME: create utility function that can be used both here and in
 : api:corpora-post-json() below.
 :)
declare
  %rest:POST("{$data}")
  %rest:path("/v1/corpora")
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
      dutil:create-corpus($name, $data/tei:teiCorpus),
      map {
        "name": $name,
        "title": $title
      }
    )
};

(:~
 : Add new corpus
 :
 : @param $data JSON object describing corpus meta data
 : @result JSON object
 :
 : FIXME: create utility function that can be used both here and in
 : api:corpora-post-tei() above.
 :)
declare
  %rest:POST("{$data}")
  %rest:path("/v1/corpora")
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
  else (
    dutil:create-corpus($json),
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
  %rest:path("/v1/corpora/{$corpusname}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:corpus-index($corpusname) {
  let $corpus := dutil:get-corpus-info-by-name($corpusname)
  let $title := $corpus?title
  let $description := $corpus?description
  let $collection := $config:corpora-root || "/" || $corpusname
  let $col := collection($collection)
  return
    if (not($corpus?name) or not(xmldb:collection-available($collection))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else map:merge((
      $corpus,
      map:entry("plays", array {
        for $tei in $col//tei:TEI
        let $paths := dutil:filepaths(base-uri($tei))
        let $sha := doc($paths?files?git)/git/sha/text()
        let $name := $paths?playname
        let $id := dutil:get-dracor-id($tei)
        let $titles := dutil:get-titles($tei)
        let $titlesEng := dutil:get-titles($tei, 'eng')
        let $years := dutil:get-years-iso($tei)
        let $authors := dutil:get-authors($tei)
        let $play-uri := $paths?uri
        let $metrics-url := $paths?files?metrics
        let $network-size := doc($metrics-url)//network/size/text()
        let $yearNormalized := dutil:get-normalized-year($tei)
        let $premiere-date := dutil:get-premiere-date($tei)
        let $source := dutil:get-source($tei)
        order by $authors[1]?name
        return map:merge((
          map:entry("id", $id),
          map:entry("uri", $play-uri),
          if ($sha) then map:entry("commit", $sha) else (),
          map:entry("name", $name),
          map:entry("title", $titles?main),
          if ($titles?sub) then map:entry("subtitle", $titles?sub) else (),
          if ($titlesEng?main) then map:entry("titleEn", $titlesEng?main) else (),
          if ($titlesEng?sub) then map:entry("subtitleEn", $titlesEng?sub) else (),
          map:entry("authors", array { $authors }),
          if (count($source)) then map:entry("source", $source) else (),
          map:entry("yearNormalized", $yearNormalized),
          map:entry("yearPrinted", $years?print),
          map:entry("yearPremiered", $years?premiere),
          if($premiere-date) then map:entry("datePremiered", $premiere-date) else (),
          map:entry("yearWritten", $years?written),
          map:entry("networkSize", xs:integer($network-size)),
          map:entry("networkdataCsvUrl", $play-uri || "/networkdata/csv"),
          map:entry("wikidataId", dutil:get-play-wikidata-id($tei))
        ))
      })
    ))
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
  %rest:path("/v1/corpora/{$corpusname}")
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
        $config:app-root || "/jobs/load-corpus.xq",
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
  %rest:path("/v1/corpora/{$corpusname}")
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
      let $url := $config:corpora-root || "/" || $corpusname || "/corpus.xml"
      return
        if ($url = $corpus/base-uri()) then
        (
          xmldb:remove($config:corpora-root || "/" || $corpusname),
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
  %rest:path("/v1/corpora/{$corpusname}/metadata")
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
      return array { $meta }
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
  %rest:path("/v1/corpora/{$corpusname}/metadata")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:corpus-meta-data-csv($corpusname) {
  api:get-corpus-meta-data-csv($corpusname)
};

(:~
 : List of metadata for all plays in a corpus
 :
 : @param $corpusname Corpus name
 : @result comma separated list of metadata for all plays
 :)
declare
  %rest:GET
  %rest:path("/v1/corpora/{$corpusname}/metadata/csv")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:corpus-meta-data-csv-endpoint($corpusname) {
  api:get-corpus-meta-data-csv($corpusname)
};

declare
  %rest:GET
  %rest:path("/v1/corpora/{$corpusname}/word-frequencies/{$elem}")
  %rest:produces("application/xml", "text/xml")
function api:word-frequencies-xml($corpusname, $elem) {
  let $collection := concat($config:corpora-root, "/", $corpusname)
  let $terms := local:get-index-keys($collection, $elem)
  return $terms
};

declare
  %rest:GET
  %rest:path("/v1/corpora/{$corpusname}/word-frequencies/{$elem}")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:word-frequencies-csv($corpusname, $elem) {
  let $collection := concat($config:corpora-root, "/", $corpusname)
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}")
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}")
  %rest:header-param("Authorization", "{$auth}")
  %output:method("json")
function api:play-delete($corpusname, $playname, $data, $auth) {
  if (not($auth)) then
    <rest:response>
      <http:response status="401"/>
    </rest:response>
  else

  let $paths := dutil:filepaths($corpusname, $playname)

  return
    if (not(doc($paths?files?tei))) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else (
      dutil:remove-corpus-sha($corpusname),
      xmldb:remove($paths?collections?play)
    )
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/metrics")
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/tei")
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
 : Get plain text representation of a single play
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @result plain text
 :)
declare
  %rest:GET
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/txt")
  %rest:produces("text/plain")
  %output:media-type("text/plain")
function api:play-txt($corpusname, $playname) {
  let $doc := dutil:get-doc($corpusname, $playname)
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else
      dutil:extract-text($doc)
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/tei")
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
      let $collection := xmldb:create-collection(
        $config:corpora-root || "/" || $corpusname, $playname
      )
      let $result := xmldb:store($collection, "tei.xml", $data/tei:TEI)
      let $_ := (
        dutil:remove-corpus-sha($corpusname),
        dutil:remove-sha($corpusname, $playname)
      )
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/rdf")
  %rest:produces("application/xml", "text/xml")
  %output:media-type("application/xml")
function api:play-rdf($corpusname, $playname) {
  let $paths := dutil:filepaths($corpusname, $playname)
  let $doc := doc($paths?files?rdf)
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/networkdata/csv")
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
      let $speakers := dutil:distinct-speakers($doc//tei:body)
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
        for $spkr in $speakers
        let $cooccurences := $segments//sgm[spkr=$spkr]/spkr/text()
        return map:entry($spkr, distinct-values($cooccurences)[.!=$spkr])
      )

      let $rows :=
        for $spkr at $pos in $speakers
          for $cooc in $links($spkr)
          where index-of($speakers, $cooc)[1] gt $pos
          let $weight := $segments//sgm[spkr=$spkr][spkr=$cooc] => count()
          return string-join(($spkr, 'Undirected',$cooc, $weight), ",")

      return string-join(("Source,Type,Target,Weight", $rows, ""), "&#10;")
};

declare function local:make-gexf-nodes($speakers, $doc) as element()* {
  for $n in $speakers?*
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
          <attvalue for="sex" value="{$sex}"></attvalue>
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/networkdata/gexf")
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
      let $speakers := dutil:distinct-speakers($doc//tei:body)
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
        for $spkr in $speakers
        let $cooccurences := $segments//sgm[spkr=$spkr]/spkr/text()
        return map:entry($spkr, distinct-values($cooccurences)[.!=$spkr])
      )

      let $nodes := local:make-gexf-nodes($info?characters, $doc)

      let $edges :=
        for $spkr at $pos in $speakers
          for $cooc in $links($spkr)
          where index-of($speakers, $cooc)[1] gt $pos
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
              <attribute id="sex" title="Sex" type="string"/>
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/networkdata/graphml")
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
      let $speakers := dutil:distinct-speakers($doc//tei:body)
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
        for $spkr in $speakers
        let $cooccurences := $segments//sgm[spkr=$spkr]/spkr/text()
        return map:entry($spkr, distinct-values($cooccurences)[.!=$spkr])
      )

      let $edges :=
        for $spkr at $pos in $speakers
          for $cooc in $links($spkr)
          where index-of($speakers, $cooc)[1] gt $pos
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
          <key attr.name="Sex" attr.type="string" for="node" id="sex"/>
          <key attr.name="Person group" attr.type="boolean" for="node" id="person-group"/>
          <key attr.name="Number of spoken words" attr.type="int" for="node" id="number-of-words"/>
          <graph edgedefault="undirected">
            {
              for $n in $info?characters?*
              let $id := $n?id
              let $label := $n?name
              let $sex := $n?sex
              let $wc := dutil:num-of-spoken-words($doc//tei:body, $id)
              return
                <node id="{$id}" xmlns="http://graphml.graphdrawing.org/xmlns">
                  <data key="label">{$label}</data>
                  {if ($sex) then <data key="sex">{$sex}</data> else ()}
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/relations/csv")
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/relations/gexf")
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

      let $nodes := local:make-gexf-nodes($info?characters, $doc)

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
              <attribute id="sex" title="Sex" type="string"/>
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/relations/graphml")
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
          <key attr.name="Sex" attr.type="string" for="node" id="sex"/>
          <key attr.name="Person group" attr.type="boolean" for="node" id="person-group"/>
          <graph edgedefault="undirected">
            {
              for $n in $info?characters?*
              let $id := $n?id
              let $label := $n?name
              let $sex := $n?sex
              return
                <node id="{$id}" xmlns="http://graphml.graphdrawing.org/xmlns">
                  <data key="label">{$label}</data>
                  {if ($sex) then <data key="sex">{$sex}</data> else ()}
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/characters")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:characters-info($corpusname, $playname) {
  let $info := dutil:characters-info($corpusname, $playname)
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/characters")
  %rest:produces("text/csv")
  %output:media-type("text/csv")
  %output:method("text")
function api:characters-info-csv($corpusname, $playname) {
  let $info := dutil:characters-info($corpusname, $playname)
  let $keys := (
    "id", "name", "sex", "isGroup",
    "numOfScenes", "numOfSpeechActs", "numOfWords", "wikidataId",
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/characters/csv")
  %output:media-type("text/csv")
  %output:method("text")
function api:characters-info-csv-ext($corpusname, $playname) {
  api:characters-info-csv($corpusname, $playname)
};

(:~
 : Get spoken text of a play (excluding stage directions)
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 : @param $sex Sex ("MALE"|"FEMALE"|"UNKNOWN")
 : @param $role Role
 : @param $relation Relation
 : @param $relation Relation role ("active"|"passive")
 : @result text
 :)
declare
  %rest:GET
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/spoken-text")
  %rest:query-param("sex", "{$sex}")
  %rest:query-param("role", "{$role}")
  %rest:query-param("relation", "{$relation}")
  %rest:query-param("relation-active", "{$relation-active}")
  %rest:query-param("relation-passive", "{$relation-passive}")
  %rest:produces("text/plain")
  %output:media-type("text/plain")
function api:spoken-text(
  $corpusname, $playname, $sex, $role, $relation, $relation-active,
  $relation-passive
) {
  let $doc := dutil:get-doc($corpusname, $playname)
  let $sexes := tokenize($sex, ',')
  return
    if (not($doc)) then
      <rest:response>
        <http:response status="404"/>
      </rest:response>
    else if (
      $sex and
      $sexes[.!="MALE" and .!="FEMALE" and .!="UNKNOWN"]
    ) then
      (
        <rest:response>
          <http:response status="400"/>
        </rest:response>,
        "sex must be ""FEMALE"", ""MALE"", or ""UNKNOWN"""
      )
    else
      let $sp := if (
        $sex or $relation or $relation-active or $relation-passive or $role
        ) then
        dutil:get-speech-filtered(
          $doc//tei:body, $sex, $role, $relation, $relation-active,
          $relation-passive
        )
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
    let $sex := $label/parent::*/@sex/string()
    let $gender := $label/parent::*/@gender/string()
    let $role := $label/parent::*/@role/string()
    let $isGroup := if ($label/parent::tei:personGrp)
    then true() else false()
    let $sp := dutil:get-speech($doc//tei:body, $id)
    return map:merge((
      map {
        "id": $id,
        "label": $label/text(),
        "isGroup": $isGroup,
        "sex": $sex,
        "roles": array {tokenize($role, '\s+')},
        "text": array {for $l in $sp return $l/normalize-space()}
      },
      if ($gender) then map:entry("gender", $gender) else ()
    ))
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/spoken-text-by-character")
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
    "/corpora/{$corpusname}/plays/{$playname}/spoken-text-by-character.json"
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/spoken-text-by-character")
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
        "ID,Label,Type,Sex,Text&#10;",
        for $t in $texts?*
        let $type := if ($t?isGroup) then "personGrp" else "person"
        let $text := string-join($t?text?*, '&#10;')
        return $t?id || ',"' || dutil:csv-escape($t?label) || '","' ||
          $type  || '","' || $t?sex || '","' ||
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/stage-directions")
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
  %rest:path("/v1/corpora/{$corpusname}/plays/{$playname}/stage-directions-with-speakers")
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

(:~
 : List plays with character identified by Wikidata ID
 :
 : @param $id Wikidata ID
 : @result Array of JSON objects
 :)
declare
  %rest:GET
  %rest:path("/v1/character/{$id}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:plays-with-character($id) {
  if (not(matches($id, '^Q[0-9]+$'))) then
    (
      <rest:response>
        <http:response status="400"/>
      </rest:response>,
      map {"error": "invalid character ID"}
    )
  else dutil:get-plays-with-character($id)
};

(:~
 : List author information from Wikidata
 :
 : @param $id Wikidata ID
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/v1/wikidata/author/{$id}")
  %rest:query-param("lang", "{$lang}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function api:authorInfo($id, $lang) {
  if (not(matches($id, '^Q[0-9]+$'))) then
    (
      <rest:response>
        <http:response status="404"/>
      </rest:response>,
      map {"error": "invalid author ID"}
    )
  else if ($lang and not(matches($lang, '^[a-z]{2}$'))) then
    (
      <rest:response>
        <http:response status="404"/>
      </rest:response>,
      map {"error": "invalid language code"}
    )
  else wd:get-author-info($id, $lang)
};

(:~
 : Endpoint for Wikidata Mix'n'match
 :
 : Returns a list of DraCor ID, title and Wikidata ID for each play in the
 : database. See https://meta.wikimedia.org/wiki/Mix'n'match/Import.
 :
 : @param $corpusname Corpus name
 : @result CSV list
 :)
declare
  %rest:GET
  %rest:path("/v1/wikidata/mixnmatch")
  %rest:produces("text/csv", "text/plain")
  %output:media-type("text/csv")
  %output:method("text")
function api:wikidata-mixnmatch() {
  wd:mixnmatch()
};

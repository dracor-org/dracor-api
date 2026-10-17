xquery version "3.1";

(:~
 : DraCor implementation of the Distributed Text Services (DTS) API 1.0
 :
 : See https://dtsapi.org/specifications/versions/v1.0/
 :
 : Collections are the DraCor corpora, below a root collection. Resources are
 : the plays. Their citation tree is derived from the TEI: `front`, `body` and
 : `back` on the first level, then nested `div`s, and `sp`, `stage`, `set`,
 : `castList` and `titlePage` elements as leaves.
 :
 : CitableUnits are identified by XPath-like references relative to
 : `tei:text`, e.g. `body/div[2]/div[1]/sp[3]`. As `ref`, `start` and `end`
 : parameters the `@xml:id` of a citable element is accepted as well.
 :)
module namespace ddts = "http://dracor.org/ns/exist/v1/dts";

import module namespace config = "http://dracor.org/ns/exist/v1/config"
  at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util"
  at "util.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
(: namespace of <dts:wrapper> in Document endpoint responses :)
declare namespace dts = "https://w3id.org/api/dts#";

declare variable $ddts:spec-version := "1.0";
declare variable $ddts:context := "https://dtsapi.org/context/v1.0.json";

(: JSON-LD context defining the terms used in `extensions` :)
declare variable $ddts:extensions-context :=
  "https://raw.githubusercontent.com/dracor-org/dracor-ontology/refs/heads/main/json-ld-contexts/dts-extension-context.json";

declare variable $ddts:base := $config:api-base || "/dts";
declare variable $ddts:collection-endpoint := $ddts:base || "/collection";
declare variable $ddts:navigation-endpoint := $ddts:base || "/navigation";
declare variable $ddts:document-endpoint := $ddts:base || "/document";

(: identifier of the root collection, e.g. https://dracor.org :)
declare variable $ddts:root-uri := replace($config:id-base, "/id$", "");

declare variable $ddts:media-types := ("application/tei+xml", "text/plain");

(: pattern of CitableUnit identifiers :)
declare variable $ddts:ref-pattern :=
  "^(front|body|back)(/(div|sp|stage|set|castList|titlePage)\[[1-9][0-9]*\])*$";

(:
 : --------------------
 : Responses
 : --------------------
 :)

(:~
 : Error response with a plain text message.
 :
 : @param $status HTTP status code
 : @param $message Error message
 :)
declare function local:error($status as xs:integer, $message as xs:string)
as item()+ {
  <rest:response>
    <http:response status="{$status}"/>
  </rest:response>,
  $message
};

(:~
 : Return the first non-empty value of a query parameter.
 :)
declare function local:param($values as xs:string*) as xs:string? {
  $values[normalize-space(.)][1]
};

(:~
 : Check the `page` parameter. DraCor DTS responses are not paginated, so only
 : the first page exists.
 :
 : @return error response or empty sequence
 :)
declare function local:check-page($page as xs:string?) as item()* {
  if (empty($page) or $page = "1") then ()
  else if (not($page castable as xs:positiveInteger)) then
    local:error(400, "The parameter 'page' must be a positive integer.")
  else
    local:error(404, "Page " || $page || " does not exist.")
};

(:~
 : Build a URL from an endpoint and query parameters, leaving out empty ones.
 :
 : @param $endpoint Endpoint URL
 : @param $params Maps with the name and value of each parameter
 :)
declare function local:url($endpoint as xs:string, $params as map(*)*)
as xs:string {
  let $query := string-join(
    for $param in $params
    where exists($param?value)
    return $param?name || "=" || encode-for-uri($param?value),
    "&amp;"
  )
  return $endpoint || (if ($query) then "?" || $query else "")
};

(:
 : --------------------
 : Identifiers
 : --------------------
 :)

(:~
 : Resolve a DTS identifier to a DraCor ID or corpus name
 :
 : Identifiers are DraCor URIs (see dutil:uri-to-id), e.g.
 : https://dracor.org/id/ger000088 for a play or https://dracor.org/id/ger for
 : a corpus. For backwards compatibility the bare play ID or corpus name is
 : accepted as well.
 :
 : @param $id Identifier
 : @return DraCor ID or corpus name, empty if $id is neither a DraCor URI nor
 :   a legal XML ID
 :)
declare function local:resolve-id($id as xs:string) as xs:string? {
  (dutil:uri-to-id($id), $id[. castable as xs:NCName])[1]
};

(:~
 : Retrieve the TEI document of a play by its identifier
 :
 : @param $resource Identifier of the play (URI or bare DraCor ID)
 : @return TEI document, empty if there is no such play
 :)
declare function local:get-tei($resource as xs:string) as element(tei:TEI)? {
  let $id := local:resolve-id($resource)
  return if ($id) then dutil:get-play-by-id($id) else ()
};

(:
 : --------------------
 : Citation tree
 : --------------------
 :)

(:~
 : Return the top-level CitableUnits of a play: front, body and back.
 :)
declare function local:top-level-units($tei as element(tei:TEI))
as element()* {
  $tei/tei:text/(tei:front | tei:body | tei:back)
};

(:~
 : Return the CitableUnits directly below a CitableUnit.
 :)
declare function local:citable-children($unit as element()) as element()* {
  if ($unit/(self::tei:front | self::tei:body | self::tei:back | self::tei:div))
  then
    $unit/(tei:div | tei:sp | tei:stage | tei:set | tei:castList | tei:titlePage)
  else ()
};

(:~
 : Return true if an element is a CitableUnit of the citation tree.
 :)
declare function local:is-citable($el as element()) as xs:boolean {
  if ($el/parent::tei:text) then
    exists($el/(self::tei:front | self::tei:body | self::tei:back))
  else
    exists($el/parent::*) and
    (some $child in local:citable-children($el/parent::*) satisfies $child is $el)
    and local:is-citable($el/parent::*)
};

(:~
 : Return the CitableUnits below a CitableUnit in document order, down to the
 : given depth.
 :
 : @param $unit CitableUnit
 : @param $depth Number of levels below $unit, -1 for all
 :)
declare function local:descendants($unit as element(), $depth as xs:integer)
as element()* {
  if ($depth eq 0) then ()
  else
    for $child in local:citable-children($unit)
    return ($child, local:descendants($child, $depth - 1))
};

(:~
 : Return all CitableUnits of a play down to the given level in document order.
 :
 : @param $tei TEI document of the play
 : @param $depth Maximum level, -1 for all
 :)
declare function local:tree($tei as element(tei:TEI), $depth as xs:integer)
as element()* {
  if ($depth eq 0) then ()
  else
    for $unit in local:top-level-units($tei)
    return ($unit, local:descendants($unit, $depth - 1))
};

(:~
 : Return the identifier of a CitableUnit, e.g. `body/div[2]/sp[3]`.
 :)
declare function local:ref($unit as element()) as xs:string {
  if ($unit/parent::tei:text) then local-name($unit)
  else
    local:ref($unit/parent::*) || "/" || local-name($unit) || "[" ||
    count($unit/preceding-sibling::*[node-name(.) eq node-name($unit)]) + 1 ||
    "]"
};

(:~
 : Return the level of a CitableUnit, 1 for front, body and back.
 :)
declare function local:level($unit as element()) as xs:integer {
  count($unit/ancestor::*[ancestor::tei:text]) + 1
};

(:~
 : Return the identifier of the parent of a CitableUnit, empty for the top
 : level.
 :)
declare function local:parent-ref($unit as element()) as xs:string? {
  if ($unit/parent::tei:text) then () else local:ref($unit/parent::*)
};

(:~
 : Return the citeType of a CitableUnit.
 :)
declare function local:cite-type($unit as element()) as xs:string {
  typeswitch ($unit)
    case element(tei:div) return
      (lower-case(normalize-space($unit/@type))[.], "div")[1]
    case element(tei:sp) return "speech"
    case element(tei:stage) return "stage_direction"
    case element(tei:set) return "setting"
    case element(tei:castList) return "cast_list"
    case element(tei:titlePage) return "title_page"
    default return local-name($unit)
};

(:~
 : Find a CitableUnit by its identifier or by the @xml:id of a citable
 : element.
 :
 : @param $tei TEI document of the play
 : @param $ref Identifier, e.g. `body/div[2]/sp[3]`, or @xml:id
 : @return CitableUnit, empty if there is none
 :)
declare function local:resolve-ref($tei as element(tei:TEI), $ref as xs:string)
as element()? {
  if (matches($ref, $ddts:ref-pattern)) then
    let $unit := fold-left(
      tokenize($ref, "/"),
      $tei/tei:text,
      function ($context, $step) {
        let $name := replace($step, "\[.*$", "")
        let $pos :=
          if (contains($step, "[")) then
            xs:integer(replace($step, "^.*\[([0-9]+)\]$", "$1"))
          else 1
        return
          $context/*[namespace-uri() eq "http://www.tei-c.org/ns/1.0"][
            local-name() eq $name
          ][$pos]
      }
    )
    return $unit[local:is-citable(.)]
  else if ($ref castable as xs:NCName) then
    ($tei/tei:text//*[@xml:id = $ref])[1][local:is-citable(.)]
  else ()
};

(:~
 : Return the CiteStructure of a set of CitableUnits, derived from the
 : citeTypes found on each level.
 :)
declare function local:cite-structure($units as element()*) as array(*) {
  array {
    for $type in distinct-values($units ! local:cite-type(.))
    let $children :=
      $units[local:cite-type(.) eq $type] ! local:citable-children(.)
    return map:merge((
      map {"@type": "CiteStructure", "citeType": $type},
      if (exists($children)) then
        map {"citeStructure": local:cite-structure($children)}
      else ()
    ))
  }
};

(:~
 : Return the citation trees of a play. There is a single, default tree.
 :)
declare function local:citation-trees($tei as element(tei:TEI)) as array(*) {
  let $top := local:top-level-units($tei)
  return array {
    if (exists($top)) then
      map {
        "@type": "CitationTree",
        "citeStructure": local:cite-structure($top)
      }
    else ()
  }
};

(:~
 : Return a short snippet of the text of a speech or stage direction.
 :)
declare function local:snippet($unit as element()) as xs:string {
  let $text :=
    if ($unit/self::tei:sp) then
      $unit//text()[not(parent::tei:speaker | parent::tei:stage | parent::tei:note)]
    else
      $unit//text()[not(parent::tei:note)]
  let $tokens := tokenize(normalize-space(string-join($text, " ")), " ")
  return
    if (count($tokens) > 5) then
      string-join(($tokens[position() < 6], "[...]", $tokens[last()]), " ")
    else
      string-join($tokens, " ")
};

(:~
 : Return the CitableUnit object for a citable element.
 :)
declare function local:citable-unit($unit as element()) as map(*) {
  let $lang := ($unit/ancestor-or-self::*/@xml:lang)[last()]/string()
  let $head := normalize-space($unit/tei:head[1])
  let $extensions := map:merge((
    if ($unit/self::tei:sp) then
      map {
        "speakers": array {
          tokenize(normalize-space($unit/@who), " ") ! replace(., "^#", "")
        }
      }
    else (),
    if ($unit/(self::tei:sp | self::tei:stage)) then
      map {"snippet": local:snippet($unit)}
    else (),
    if ($unit/@xml:id) then map {"xmlId": $unit/@xml:id/string()} else ()
  ))
  return map:merge((
    map {
      "identifier": local:ref($unit),
      "@type": "CitableUnit",
      "level": local:level($unit),
      "parent": local:parent-ref($unit),
      "citeType": local:cite-type($unit)
    },
    if ($head) then
      map {
        "dublinCore": map {
          "title": array {
            map:merge((
              map {"value": $head},
              if ($lang) then map {"lang": $lang} else ()
            ))
          }
        }
      }
    else (),
    if (map:size($extensions) gt 0) then
      map {
        "extensions":
          map:merge((map {"@context": $ddts:extensions-context}, $extensions))
      }
    else ()
  ))
};

(:
 : --------------------
 : Collections and Resources
 : --------------------
 :)

(:~
 : Return the names of all corpora, sorted.
 :)
declare function local:corpus-names() as xs:string* {
  for $corpus in
    collection($config:corpora-root)/(tei:dracorCorpus | tei:teiCorpus)
  let $name := dutil:get-corpus-info($corpus)?name
  order by $name
  return $name
};

(:~
 : Return the TEI documents of the plays of a corpus.
 :)
declare function local:corpus-plays($corpusname as xs:string)
as element(tei:TEI)* {
  collection($config:corpora-root || "/" || $corpusname)/tei:TEI
};

(:~
 : Return the root Collection object, without members.
 :)
declare function local:root-object() as map(*) {
  map {
    "@id": $ddts:root-uri,
    "@type": "Collection",
    "title": "DraCor",
    "description": "Drama Corpora Project",
    "totalParents": 0,
    "totalChildren": count(local:corpus-names()),
    "collection": $ddts:collection-endpoint || "{?id,page,nav}"
  }
};

(:~
 : Return the Collection object for a corpus, without members.
 :)
declare function local:corpus-object($corpusname as xs:string) as map(*) {
  let $info := dutil:get-corpus-info-by-name($corpusname)
  let $uri := dutil:corpus-uri($corpusname)
  return map:merge((
    map {
      "@id": $uri,
      "@type": "Collection",
      "title": ($info?title[.], $corpusname)[1],
      "totalParents": 1,
      "totalChildren": count(local:corpus-plays($corpusname)),
      "collection":
        $ddts:collection-endpoint || "?id=" || $uri || "{&amp;page,nav}"
    },
    if ($info?description) then map {"description": $info?description} else ()
  ))
};

(:~
 : Return Dublin Core metadata of a play.
 :)
declare function local:play-dublin-core($tei as element(tei:TEI)) as map(*) {
  let $lang := $tei/@xml:lang/string()
  let $titles := dutil:get-titles($tei)
  let $authors := dutil:get-authors($tei)
  let $localized := function ($value as xs:string) as map(*) {
    map:merge((
      map {"value": $value},
      if ($lang) then map {"lang": $lang} else ()
    ))
  }
  return map:merge((
    if ($titles?main) then
      map {"title": array {$localized($titles?main)}}
    else (),
    if (exists($authors)) then
      map {"creator": array {$authors ! $localized(?name)}}
    else (),
    if ($lang) then map {"language": array {$lang}} else ()
  ))
};

(:~
 : Return DraCor-specific metadata of a play.
 :)
declare function local:play-extensions($tei as element(tei:TEI)) as map(*) {
  let $wikidata-id := dutil:get-play-wikidata-id($tei)
  let $year := dutil:get-normalized-year($tei)
  let $paths := dutil:filepaths(base-uri($tei))
  let $wordcount := doc($paths?files?metrics)/metrics/text/string()
  return map:merge((
    map {"@context": $ddts:extensions-context},
    if (exists($year)) then map {"yearNormalized": $year[1]} else (),
    if ($wikidata-id) then
      map {"wikidataUri": "http://www.wikidata.org/entity/" || $wikidata-id}
    else (),
    map {
      "numOfSpeakers": count(dutil:distinct-speakers($tei)),
      "numOfSegments": count(dutil:get-segments($tei))
    },
    if ($wordcount castable as xs:integer) then
      map {"wordCountText": xs:integer($wordcount)}
    else ()
  ))
};

(:~
 : Return the Resource object for a play.
 :
 : @param $tei TEI document of the play
 : @param $with-trees Whether to include the citation trees
 :)
declare function local:resource-object(
  $tei as element(tei:TEI),
  $with-trees as xs:boolean
) as map(*) {
  let $id := dutil:get-dracor-id($tei)
  let $uri := dutil:play-uri($id)
  let $paths := dutil:filepaths(base-uri($tei))
  return map:merge((
    map {
      "@id": $uri,
      "@type": "Resource",
      "title": (dutil:get-titles($tei)?main, $id)[1],
      "totalParents": 1,
      "totalChildren": 0,
      "collection":
        $ddts:collection-endpoint || "?id=" || $uri || "{&amp;nav}",
      "navigation":
        $ddts:navigation-endpoint || "?resource=" || $uri ||
        "{&amp;ref,down,start,end,tree,page}",
      "document":
        $ddts:document-endpoint || "?resource=" || $uri ||
        "{&amp;ref,start,end,tree,mediaType}",
      "download": $paths?uri || "/tei",
      "mediaTypes": array {$ddts:media-types},
      "dublinCore": local:play-dublin-core($tei),
      "extensions": local:play-extensions($tei)
    },
    if ($with-trees) then
      map {"citationTrees": local:citation-trees($tei)}
    else ()
  ))
};

(:~
 : Add the properties of a top-level response object.
 :)
declare function local:top-level($object as map(*)) as map(*) {
  map:merge((
    map {"@context": $ddts:context, "dtsVersion": $ddts:spec-version},
    $object
  ))
};

(:
 : --------------------
 : Entry endpoint
 : --------------------
 :)

(:~
 : DTS entry endpoint
 :)
declare
  %rest:GET
  %rest:path("/v1/dts")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ddts:entry-point() as map(*) {
  local:top-level(map {
    "@id": $ddts:base,
    "@type": "EntryPoint",
    "collection": $ddts:collection-endpoint || "{?id,page,nav}",
    "navigation":
      $ddts:navigation-endpoint || "{?resource,ref,start,end,down,tree,page}",
    "document":
      $ddts:document-endpoint || "{?resource,ref,start,end,tree,mediaType}"
  })
};

(:
 : --------------------
 : Collection endpoint
 : --------------------
 :)

(:~
 : DTS collection endpoint
 :
 : @param $id Identifier of the root collection, a corpus or a play. Without
 :   it the root collection is returned.
 : @param $page Page of the members, only page 1 exists
 : @param $nav `children` (default) or `parents`
 :)
declare
  %rest:GET
  %rest:path("/v1/dts/collection")
  %rest:query-param("id", "{$id}")
  %rest:query-param("page", "{$page}")
  %rest:query-param("nav", "{$nav}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ddts:collection(
  $id as xs:string*,
  $page as xs:string*,
  $nav as xs:string*
) as item()+ {
  let $id := local:param($id)
  let $nav := (local:param($nav), "children")[1]
  let $name := if ($id) then local:resolve-id($id) else ()
  let $page-error := local:check-page(local:param($page))
  return
    if (not($nav = ("children", "parents"))) then
      local:error(
        400,
        "The value of the parameter 'nav' must be 'children' or 'parents'."
      )
    else if (exists($page-error)) then
      $page-error
    else if (empty($id) or $id = ($ddts:root-uri, $config:api-origin)) then
      local:top-level(map:merge((
        local:root-object(),
        map {
          "member": array {
            if ($nav eq "parents") then ()
            else local:corpus-names() ! local:corpus-object(.)
          }
        }
      )))
    else if ($name and dutil:get-corpus($name)) then
      local:top-level(map:merge((
        local:corpus-object($name),
        map {
          "member": array {
            if ($nav eq "parents") then
              local:root-object()
            else
              local:corpus-plays($name) ! local:resource-object(., false())
          }
        }
      )))
    else if ($name and dutil:get-play-by-id($name)) then
      let $tei := dutil:get-play-by-id($name)
      let $corpusname := dutil:filepaths(base-uri($tei))?corpusname
      return local:top-level(map:merge((
        local:resource-object($tei, true()),
        if ($nav eq "parents") then
          map {"member": array {local:corpus-object($corpusname)}}
        else ()
      )))
    else
      local:error(
        404,
        "The identifier '" || $id || "' does not identify a collection or resource."
      )
};

(:
 : --------------------
 : Navigation endpoint
 : --------------------
 :)

(:~
 : DTS navigation endpoint
 :)
declare
  %rest:GET
  %rest:path("/v1/dts/navigation")
  %rest:query-param("resource", "{$resource}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("down", "{$down}")
  %rest:query-param("tree", "{$tree}")
  %rest:query-param("page", "{$page}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ddts:navigation(
  $resource as xs:string*,
  $ref as xs:string*,
  $start as xs:string*,
  $end as xs:string*,
  $down as xs:string*,
  $tree as xs:string*,
  $page as xs:string*
) as item()+ {
  local:error(501, "Not implemented yet.")
};

(:
 : --------------------
 : Document endpoint
 : --------------------
 :)

(:~
 : DTS document endpoint
 :)
declare
  %rest:GET
  %rest:path("/v1/dts/document")
  %rest:query-param("resource", "{$resource}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("tree", "{$tree}")
  %rest:query-param("mediaType", "{$media-type}")
  %rest:header-param("Accept", "{$accept}")
  %rest:produces("application/tei+xml", "application/xml", "text/plain")
  %output:method("xml")
function ddts:document(
  $resource as xs:string*,
  $ref as xs:string*,
  $start as xs:string*,
  $end as xs:string*,
  $tree as xs:string*,
  $media-type as xs:string*,
  $accept as xs:string*
) as item()+ {
  local:error(501, "Not implemented yet.")
};

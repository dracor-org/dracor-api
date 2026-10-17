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

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";
(: namespace of <dts:wrapper> in Document endpoint responses :)
declare namespace dts = "https://w3id.org/api/dts#";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

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
declare function local:error(
  $status as xs:integer,
  $message as xs:string
) as item()+ {
  <rest:response><http:response status="{ $status }" /></rest:response>,
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
  if (empty($page) or $page = "1") then (
  ) else if (not($page castable as xs:positiveInteger)) then
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
declare function local:url(
  $endpoint as xs:string,
  $params as map(*)*
) as xs:string {
  let $query := string-join(
    for $param in $params
    where exists($param?value)
    return $param?name || "=" || encode-for-uri($param?value),
    "&amp;"
  )
  return $endpoint ||
    (
      if ($query) then
        "?" || $query
      else
        ""
    )
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
 : a legal XML ID
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
  return if ($id) then
    dutil:get-play-by-id($id)
  else (
  )
};

(:
 : --------------------
 : Citation tree
 : --------------------
 :)

(:~
 : Return the top-level CitableUnits of a play: front, body and back.
 :)
declare function local:top-level-units($tei as element(tei:TEI)) as element()* {
  $tei/tei:text/(tei:front | tei:body | tei:back)
};

(:~
 : Return the CitableUnits directly below a CitableUnit.
 :)
declare function local:citable-children($unit as element()) as element()* {
  if (
    $unit/(self::tei:front | self::tei:body | self::tei:back | self::tei:div)
  ) then
    $unit/(
      tei:div | tei:sp | tei:stage | tei:set | tei:castList | tei:titlePage
    )
  else (
  )
};

(:~
 : Return true if an element is a CitableUnit of the citation tree.
 :)
declare function local:is-citable($el as element()) as xs:boolean {
  if ($el/parent::tei:text) then
    exists($el/(self::tei:front | self::tei:body | self::tei:back))
  else
    exists($el/parent::*) and
      (
        some
          $child in
          local:citable-children($el/parent::*) satisfies
          $child is $el
      ) and
      local:is-citable($el/parent::*)
};

(:~
 : Return the CitableUnits below a CitableUnit in document order, down to the
 : given depth.
 :
 : @param $unit CitableUnit
 : @param $depth Number of levels below $unit, -1 for all
 :)
declare function local:descendants(
  $unit as element(),
  $depth as xs:integer
) as element()* {
  if ($depth eq 0) then (
  ) else
    for $child in local:citable-children($unit)
    return ($child, local:descendants($child, $depth - 1))
};

(:~
 : Return all CitableUnits of a play down to the given level in document order.
 :
 : @param $tei TEI document of the play
 : @param $depth Maximum level, -1 for all
 :)
declare function local:tree(
  $tei as element(tei:TEI),
  $depth as xs:integer
) as element()* {
  if ($depth eq 0) then (
  ) else
    for $unit in local:top-level-units($tei)
    return ($unit, local:descendants($unit, $depth - 1))
};

(:~
 : Return the identifier of a CitableUnit, e.g. `body/div[2]/sp[3]`.
 :)
declare function local:ref($unit as element()) as xs:string {
  if ($unit/parent::tei:text) then
    local-name($unit)
  else
    local:ref($unit/parent::*) ||
      "/" ||
      local-name($unit) ||
      "[" ||
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
  if ($unit/parent::tei:text) then (
  ) else
    local:ref($unit/parent::*)
};

(:~
 : Return the citeType of a CitableUnit.
 :)
declare function local:cite-type($unit as element()) as xs:string {
  typeswitch ($unit)
    case element(tei:div) return
      (lower-case(normalize-space($unit/@type))[.], "div")[1]
    case element(tei:sp) return
      "speech"
    case element(tei:stage) return
      "stage_direction"
    case element(tei:set) return
      "setting"
    case element(tei:castList) return
      "cast_list"
    case element(tei:titlePage) return
      "title_page"

    default return
      local-name($unit)
};

(:~
 : Find a CitableUnit by its identifier or by the @xml:id of a citable
 : element.
 :
 : @param $tei TEI document of the play
 : @param $ref Identifier, e.g. `body/div[2]/sp[3]`, or @xml:id
 : @return CitableUnit, empty if there is none
 :)
declare function local:resolve-ref(
  $tei as element(tei:TEI),
  $ref as xs:string
) as element()? {
  if (matches($ref, $ddts:ref-pattern)) then
    let $unit := fold-left(
      tokenize($ref, "/"),
      $tei/tei:text,
      function ($context, $step) {
        let $name := replace($step, "\[.*$", "")
        let $pos := if (contains($step, "[")) then
          xs:integer(replace($step, "^.*\[([0-9]+)\]$", "$1"))
        else
          1
        return $context/*[namespace-uri() eq
          "http://www.tei-c.org/ns/1.0"][local-name() eq $name][$pos]
      }
    )
    return $unit[local:is-citable(.)]
  else if ($ref castable as xs:NCName) then
    ($tei/tei:text//*[@xml:id = $ref])[1][local:is-citable(.)]
  else (
  )
};

(:~
 : Return the CiteStructure of a set of CitableUnits, derived from the
 : citeTypes found on each level.
 :)
declare function local:cite-structure($units as element()*) as array(*) {
  array
    {
      for $type in distinct-values($units!local:cite-type(.))
      let $children := $units[local:cite-type(.) eq
        $type]!local:citable-children(.)
      return map:merge(
        (
          map {"@type": "CiteStructure", "citeType": $type},
          if (exists($children)) then
            map {"citeStructure": local:cite-structure($children)}
          else (
          )
        )
      )
    }
};

(:~
 : Return the citation trees of a play. There is a single, default tree.
 :)
declare function local:citation-trees($tei as element(tei:TEI)) as array(*) {
  let $top := local:top-level-units($tei)
  return array
    {
      if (exists($top)) then
        map {
          "@type": "CitationTree",
          "citeStructure": local:cite-structure($top)
        }
      else (
      )
    }
};

(:~
 : Return a short snippet of the text of a speech or stage direction.
 :)
declare function local:snippet($unit as element()) as xs:string {
  (:
   : excluded text: notes, and speaker labels and stage directions in speeches
   : (written as a FLWOR expression, as eXist fails on the equivalent
   : predicate with not())
   :)
  let $excluded := if ($unit/self::tei:sp) then (
    "note", "speaker", "stage"
  ) else
    "note"
  let $text :=
    for $node in $unit//text()
    where not(local-name($node/parent::*) = $excluded)
    return $node
  let $tokens := tokenize(normalize-space(string-join($text, " ")), " ")
  return if (count($tokens) > 5) then
    string-join(($tokens[position() < 6], "[...]", $tokens[last()]), " ")
  else
    string-join($tokens, " ")
};

(:~
 : Return the CitableUnit object for a citable element.
 :)
declare function local:citable-unit($unit as element()) as map(*) {
  local:citable-unit($unit, local:ref($unit), local:parent-ref($unit))
};

(:~
 : Return the CitableUnit objects for citable elements in document order.
 :
 : The identifiers are built incrementally, reusing the identifier of the
 : parent, which is much faster for large numbers of units than computing
 : each one from scratch.
 :)
declare function local:citable-units($units as element()*) as map(*)* {
  (: identifiers by node ID; the parent of the first units may be missing :)
  let $refs := fold-left(
    $units,
    map {},
    function ($refs as map(*), $unit as element()) {
      let $parent := $unit/parent::*
      let $parent-id := util:node-id($parent)
      (: no sequence with a fallback here, eXist would evaluate both :)
      let $parent-ref := if ($parent/self::tei:text) then (
      ) else if (map:contains($refs, $parent-id)) then
        $refs($parent-id)?ref
      else
        local:ref($parent)
      let $ref := if ($parent/self::tei:text) then
        local-name($unit)
      else
        $parent-ref ||
          "/" ||
          local-name($unit) ||
          "[" ||
          count($unit/preceding-sibling::*[node-name(.) eq node-name($unit)]) +
            1 ||
          "]"
      return map:put(
        $refs,
        util:node-id($unit),
        map {"ref": $ref, "parent": $parent-ref}
      )
    }
  )
  for $unit in $units
  let $entry := $refs(util:node-id($unit))
  return local:citable-unit($unit, $entry?ref, $entry?parent)
};

(:~
 : Return the CitableUnit object for a citable element with a given
 : identifier and parent identifier.
 :)
declare function local:citable-unit(
  $unit as element(),
  $ref as xs:string,
  $parent-ref as xs:string?
) as map(*) {
  let $lang := ($unit/ancestor-or-self::*/@xml:lang)[last()]/string()
  let $head := normalize-space($unit/tei:head[1])
  let $extensions := map:merge(
    (
      if ($unit/self::tei:sp) then
        map {
          "speakers":
            array
              {
                tokenize(normalize-space($unit/@who), " ")!replace(., "^#", "")
              }
        }
      else (
      ),
      if ($unit/(self::tei:sp | self::tei:stage)) then
        map {"snippet": local:snippet($unit)}
      else (
      ),
      if ($unit/@xml:id) then
        map {"xmlId": $unit/@xml:id/string()}
      else (
      )
    )
  )
  return map:merge(
    (
      map {
        "identifier": $ref,
        "@type": "CitableUnit",
        "level": local:level($unit),
        "parent": $parent-ref,
        "citeType": local:cite-type($unit)
      },
      if ($head) then
        map {
          "dublinCore":
            map {
              "title":
                array
                  {
                    map:merge(
                      (
                        map {"value": $head},
                        if ($lang) then
                          map {"lang": $lang}
                        else (
                        )
                      )
                    )
                  }
            }
        }
      else (
      ),
      if (map:size($extensions) gt 0) then
        map {
          "extensions":
            map:merge((map {"@context": $ddts:extensions-context}, $extensions))
        }
      else (
      )
    )
  )
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
declare function local:corpus-plays(
  $corpusname as xs:string
) as element(tei:TEI)* {
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
  return map:merge(
    (
      map {
        "@id": $uri,
        "@type": "Collection",
        "title": ($info?title[.], $corpusname)[1],
        "totalParents": 1,
        "totalChildren": count(local:corpus-plays($corpusname)),
        "collection":
          $ddts:collection-endpoint || "?id=" || $uri || "{&amp;page,nav}"
      },
      if ($info?description) then
        map {"description": $info?description}
      else (
      )
    )
  )
};

(:~
 : Return Dublin Core metadata of a play.
 :)
declare function local:play-dublin-core($tei as element(tei:TEI)) as map(*) {
  let $lang := $tei/@xml:lang/string()
  let $titles := dutil:get-titles($tei)
  let $authors := dutil:get-authors($tei)
  let $localized := function ($value as xs:string) as map(*) {
    map:merge(
      (
        map {"value": $value},
        if ($lang) then
          map {"lang": $lang}
        else (
        )
      )
    )
  }
  return map:merge(
    (
      if ($titles?main) then
        map {"title": array { $localized($titles?main) }}
      else (
      ),
      if (exists($authors)) then
        map {"creator": array { $authors!$localized(?name) }}
      else (
      ),
      if ($lang) then
        map {"language": array { $lang }}
      else (
      )
    )
  )
};

(:~
 : Return DraCor-specific metadata of a play.
 :)
declare function local:play-extensions($tei as element(tei:TEI)) as map(*) {
  let $wikidata-id := dutil:get-play-wikidata-id($tei)
  let $year := dutil:get-normalized-year($tei)
  let $paths := dutil:filepaths(base-uri($tei))
  let $wordcount := doc($paths?files?metrics)/metrics/text/string()
  return map:merge(
    (
      map {"@context": $ddts:extensions-context},
      if (exists($year)) then
        map {"yearNormalized": $year[1]}
      else (
      ),
      if ($wikidata-id) then
        map {"wikidataUri": "http://www.wikidata.org/entity/" || $wikidata-id}
      else (
      ),
      map {
        "numOfSpeakers": count(dutil:distinct-speakers($tei)),
        "numOfSegments": count(dutil:get-segments($tei))
      },
      if ($wordcount castable as xs:integer) then
        map {"wordCountText": xs:integer($wordcount)}
      else (
      )
    )
  )
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
  return map:merge(
    (
      map {
        "@id": $uri,
        "@type": "Resource",
        "title": (dutil:get-titles($tei)?main, $id)[1],
        "totalParents": 1,
        "totalChildren": 0,
        "collection":
          $ddts:collection-endpoint || "?id=" || $uri || "{&amp;nav}",
        "navigation":
          $ddts:navigation-endpoint ||
            "?resource=" ||
            $uri ||
            "{&amp;ref,down,start,end,tree,page}",
        "document":
          $ddts:document-endpoint ||
            "?resource=" ||
            $uri ||
            "{&amp;ref,start,end,tree,mediaType}",
        "download": $paths?uri || "/tei",
        "mediaTypes": array { $ddts:media-types },
        "dublinCore": local:play-dublin-core($tei),
        "extensions": local:play-extensions($tei)
      },
      if ($with-trees) then
        map {"citationTrees": local:citation-trees($tei)}
      else (
      )
    )
  )
};

(:~
 : Add the properties of a top-level response object.
 :)
declare function local:top-level($object as map(*)) as map(*) {
  map:merge(
    (map {"@context": $ddts:context, "dtsVersion": $ddts:spec-version}, $object)
  )
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
  local:top-level(
    map {
      "@id": $ddts:base,
      "@type": "EntryPoint",
      "collection": $ddts:collection-endpoint || "{?id,page,nav}",
      "navigation":
        $ddts:navigation-endpoint || "{?resource,ref,start,end,down,tree,page}",
      "document":
        $ddts:document-endpoint || "{?resource,ref,start,end,tree,mediaType}"
    }
  )
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
 : it the root collection is returned.
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
  let $name := if ($id) then
    local:resolve-id($id)
  else (
  )
  let $page-error := local:check-page(local:param($page))
  return if (not($nav = ("children", "parents"))) then
    local:error(
      400,
      "The value of the parameter 'nav' must be 'children' or 'parents'."
    )
  else if (exists($page-error)) then
    $page-error
  else if (empty($id) or $id = ($ddts:root-uri, $config:api-origin)) then
    local:top-level(
      map:merge(
        (
          local:root-object(),
          map {
            "member":
              array
                {
                  if ($nav eq "parents") then (
                  ) else
                    local:corpus-names()!local:corpus-object(.)
                }
          }
        )
      )
    )
  else if ($name and dutil:get-corpus($name)) then
    local:top-level(
      map:merge(
        (
          local:corpus-object($name),
          map {
            "member":
              array
                {
                  if ($nav eq "parents") then
                    local:root-object()
                  else
                    local:corpus-plays($name)!local:resource-object(., false())
                }
          }
        )
      )
    )
  else if ($name and dutil:get-play-by-id($name)) then
    let $tei := dutil:get-play-by-id($name)
    let $corpusname := dutil:filepaths(base-uri($tei))?corpusname
    return local:top-level(
      map:merge(
        (
          local:resource-object($tei, true()),
          if ($nav eq "parents") then
            map {"member": array { local:corpus-object($corpusname) }}
          else (
          )
        )
      )
    )
  else
    local:error(
      404,
      "The identifier '" ||
        $id ||
        "' does not identify a collection or resource."
    )
};

(:
 : --------------------
 : Navigation endpoint
 : --------------------
 :)

(:~
 : Return the position of a node in a sequence of nodes.
 :)
declare function local:index-of(
  $nodes as node()*,
  $node as node()
) as xs:integer? {
  (
    for $n at $i in $nodes
    where $n is $node
    return $i
  )[1]
};

(:~
 : Return the CitableUnits of a range in document order: from the start unit
 : up to the last descendant of the end unit, down to the given level.
 :
 : @param $tei TEI document of the play
 : @param $start First CitableUnit of the range
 : @param $end Last CitableUnit of the range
 : @param $max-level Deepest level to include, -1 for all
 :)
declare function local:range(
  $tei as element(tei:TEI),
  $start as element(),
  $end as element(),
  $max-level as xs:integer
) as element()* {
  let $all := local:tree($tei, -1)
  let $first := local:index-of($all, $start)
  let $last := local:index-of($all, ($end, local:descendants($end, -1))[last()])
  for $unit in subsequence($all, $first, $last - $first + 1)
  where $max-level lt 0 or local:level($unit) le $max-level
  return $unit
};

(:~
 : DTS navigation endpoint
 :
 : @param $resource Identifier of the play
 : @param $ref CitableUnit to navigate from
 : @param $start First CitableUnit of a range
 : @param $end Last CitableUnit of a range
 : @param $down Depth of the citation tree to return, -1 for all levels
 : @param $tree Identifier of a citation tree; only the default tree exists
 : @param $page Page of the members, only page 1 exists
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
  let $resource := local:param($resource)
  let $ref := local:param($ref)
  let $start := local:param($start)
  let $end := local:param($end)
  let $down-param := local:param($down)
  let $down := if ($down-param castable as xs:integer) then
    xs:integer($down-param)
  else (
  )
  let $tree := local:param($tree)
  let $page := local:param($page)
  let $page-error := local:check-page($page)
  let $tei := if ($resource) then
    local:get-tei($resource)
  else (
  )
  return if (empty($resource)) then
    local:error(400, "The parameter 'resource' is required.")
  else if ($ref and ($start or $end)) then
    local:error(
      400,
      "The parameter 'ref' cannot be combined with 'start' and 'end'."
    )
  else if (($start and empty($end)) or ($end and empty($start))) then
    local:error(400, "The parameters 'start' and 'end' must be used together.")
  else if ($down-param and (empty($down) or $down lt -1)) then
    local:error(400, "The parameter 'down' must be an integer of -1 or more.")
  else if (empty($down) and empty($ref) and empty($start)) then
    local:error(
      400,
      "At least one of the parameters 'down', 'ref' or 'start' and 'end' is required."
    )
  else if ($down eq 0 and empty($ref)) then
    local:error(400, "The parameter 'down=0' requires 'ref'.")
  else if (exists($page-error)) then
    $page-error
  else if (empty($tei)) then
    local:error(404, "Resource '" || $resource || "' not found.")
  else if ($tree) then
    local:error(404, "Citation tree '" || $tree || "' not found.")
  else
    let $ref-unit := if ($ref) then
      local:resolve-ref($tei, $ref)
    else (
    )
    let $start-unit := if ($start) then
      local:resolve-ref($tei, $start)
    else (
    )
    let $end-unit := if ($end) then
      local:resolve-ref($tei, $end)
    else (
    )
    return if ($ref and empty($ref-unit)) then
      local:error(404, "CitableUnit '" || $ref || "' not found.")
    else if ($start and empty($start-unit)) then
      local:error(404, "CitableUnit '" || $start || "' not found.")
    else if ($end and empty($end-unit)) then
      local:error(404, "CitableUnit '" || $end || "' not found.")
    else if ($start-unit and $end-unit << $start-unit) then
      local:error(400, "The range ends before it starts.")
    else
      let $members := if (empty($down)) then (
      ) else if ($ref-unit and $down eq 0) then
        if ($ref-unit/parent::tei:text) then
          local:top-level-units($tei)
        else
          local:citable-children($ref-unit/parent::*)
      else if ($ref-unit) then (
        $ref-unit, local:descendants($ref-unit, $down)
      ) else if ($start-unit) then
        local:range(
          $tei,
          $start-unit,
          $end-unit,
          if ($down lt 0) then
            -1
          else
            max((local:level($start-unit), local:level($end-unit))) + $down
        )
      else
        local:tree($tei, $down)
      let $id := local:url(
        $ddts:navigation-endpoint,
        (
          map {"name": "resource", "value": $resource},
          map {"name": "ref", "value": $ref},
          map {"name": "start", "value": $start},
          map {"name": "end", "value": $end},
          map {"name": "down", "value": $down-param},
          map {"name": "page", "value": $page}
        )
      )
      return local:top-level(
        map:merge(
          (
            map {
              "@id": $id,
              "@type": "Navigation",
              "resource": local:resource-object($tei, true())
            },
            if ($ref-unit) then
              map {"ref": local:citable-unit($ref-unit)}
            else (
            ),
            if ($start-unit) then
              map {
                "start": local:citable-unit($start-unit),
                "end": local:citable-unit($end-unit)
              }
            else (
            ),
            if (exists($down)) then
              map {"member": array { local:citable-units($members) }}
            else (
            )
          )
        )
      )
};

(:
 : --------------------
 : Document endpoint
 : --------------------
 :)

(:~
 : Return the quality value an Accept header gives a media type, taking it
 : from the most specific matching media range. Without Accept header any
 : media type is acceptable.
 :)
declare function local:accept-quality(
  $accept as xs:string?,
  $type as xs:string
) as xs:double {
  if (not(normalize-space($accept))) then
    1
  else
    let $qualities :=
      for $range in tokenize($accept, ",")
      let $parts := tokenize($range, ";")!normalize-space(.)
      let $media-range := lower-case($parts[1])
      let $q := substring-after($parts[starts-with(., "q=")][1], "q=")
      let $specificity := if ($media-range eq $type) then
        3
      else if ($media-range eq substring-before($type, "/") || "/*") then
        2
      else if ($media-range eq "*/*") then
        1
      else
        0
      where $specificity gt 0
      order by $specificity descending
      return if ($q castable as xs:double) then
        xs:double($q)
      else
        1
    return ($qualities, 0)[1]
};

(:~
 : Return the XPath of a CitableUnit for the attributes of <dts:wrapper>.
 :)
declare function local:xpath($unit as element()) as xs:string {
  "/TEI/text/" || local:ref($unit)
};

(:~
 : Return the part of a list of nodes that lies within a range: nodes
 : completely within the range are copied, ancestors of its start or end are
 : copied with only the part of their content that lies within the range.
 :)
declare function local:prune(
  $nodes as node()*,
  $start as element(),
  $end as element()
) as node()* {
  for $node in $nodes
  return if (
    $node is $end or ($node is $start and empty($end intersect $start//*))
  ) then
    $node
  else if (
    exists($node intersect ($start/ancestor-or-self::*, $end/ancestor::*))
  ) then
    element {node-name($node)} {
      $node/@*, local:prune($node/node(), $start, $end)
    }
  else if ($node >> $start and $node << $end) then
    $node
  else (
  )
};

(:~
 : Return the content of a range of CitableUnits, from the start unit to the
 : end of the end unit, within their closest common ancestor.
 :)
declare function local:range-content(
  $start as element(),
  $end as element()
) as node()* {
  let $common := (
    $start/ancestor-or-self::* intersect $end/ancestor-or-self::*
  )[last()]
  return if ($common is $start) then
    local:prune($start, $start, $end)
  else
    local:prune($common/node(), $start, $end)
};

(:~
 : DTS document endpoint
 :
 : The full TEI document, or the requested CitableUnit or range embedded in
 : <dts:wrapper> after the teiHeader of the play. With `mediaType=text/plain`
 : the text of the play or the fragment is returned instead.
 :
 : TEI is sent as application/tei+xml unless the Accept header prefers
 : application/xml, as web browsers do, so that they display the XML.
 :
 : @param $resource Identifier of the play
 : @param $ref CitableUnit to return
 : @param $start First CitableUnit of a range to return
 : @param $end Last CitableUnit of a range to return
 : @param $tree Identifier of a citation tree; only the default tree exists
 : @param $media-type `application/tei+xml` (default) or `text/plain`
 : @param $accept Accept header
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
  let $resource := local:param($resource)
  let $ref := local:param($ref)
  let $start := local:param($start)
  let $end := local:param($end)
  let $tree := local:param($tree)
  (: a "+" in an unencoded query parameter arrives as space :)
  let $media-type := (
    local:param($media-type)!replace(normalize-space(.), " ", "+"),
    "application/tei+xml"
  )[1]
  let $tei := if ($resource) then
    local:get-tei($resource)
  else (
  )
  return if (empty($resource)) then
    local:error(400, "The parameter 'resource' is required.")
  else if ($ref and ($start or $end)) then
    local:error(
      400,
      "The parameter 'ref' cannot be combined with 'start' and 'end'."
    )
  else if (($start and empty($end)) or ($end and empty($start))) then
    local:error(400, "The parameters 'start' and 'end' must be used together.")
  else if (empty($tei)) then
    local:error(404, "Resource '" || $resource || "' not found.")
  else if (not($media-type = $ddts:media-types)) then
    local:error(404, "Media type '" || $media-type || "' is not available.")
  else if ($tree and ($ref or $start)) then
    local:error(404, "Citation tree '" || $tree || "' not found.")
  else
    let $ref-unit := if ($ref) then
      local:resolve-ref($tei, $ref)
    else (
    )
    let $start-unit := if ($start) then
      local:resolve-ref($tei, $start)
    else (
    )
    let $end-unit := if ($end) then
      local:resolve-ref($tei, $end)
    else (
    )
    return if ($ref and empty($ref-unit)) then
      local:error(404, "CitableUnit '" || $ref || "' not found.")
    else if ($start and empty($start-unit)) then
      local:error(404, "CitableUnit '" || $start || "' not found.")
    else if ($end and empty($end-unit)) then
      local:error(404, "CitableUnit '" || $end || "' not found.")
    else if ($start-unit and $end-unit << $start-unit) then
      local:error(400, "The range ends before it starts.")
    else
      let $wrapper := if ($ref-unit) then
        <dts:wrapper>{ $ref-unit }</dts:wrapper>
      else if ($start-unit) then
        <dts:wrapper
          end="{ local:xpath($end-unit) }"
          start="{ local:xpath($start-unit) }"
        >{ local:range-content($start-unit, $end-unit) }</dts:wrapper>
      else (
      )
      let $content-type := if ($media-type eq "text/plain") then
        "text/plain; charset=utf-8"
      else if (
        local:accept-quality(string-join($accept, ","), "application/xml") gt
          local:accept-quality(string-join($accept, ","), "application/tei+xml")
      ) then
        "application/xml"
      else
        "application/tei+xml"
      let $collection-link := $ddts:collection-endpoint ||
        "?id=" ||
        dutil:play-uri(dutil:get-dracor-id($tei))
      return (
        <rest:response>
          <http:response status="200">
            <http:header name="Content-Type" value="{ $content-type }" />
            <http:header
              name="Link"
              value="&lt;{
                $collection-link
              }&gt;; rel=&quot;collection&quot;" />
            <http:header name="Vary" value="Accept" />
          </http:response>
        </rest:response>,
        if ($media-type eq "text/plain") then
          dutil:extract-text(($wrapper, $tei)[1])
        else if ($wrapper) then
          <TEI xmlns="http://www.tei-c.org/ns/1.0">
            { $tei/tei:teiHeader, $wrapper }
          </TEI>
        else
          $tei
      )
};

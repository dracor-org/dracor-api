xquery version "3.1";

(:~
 : Module providing utility functions for dracor.
 :)
module namespace dutil = "http://dracor.org/ns/exist/v1/util";

import module namespace functx="http://www.functx.com";
import module namespace config = "http://dracor.org/ns/exist/v1/config"
  at "config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace json = "http://www.w3.org/2013/XSL/json";

(:~
 : Provide map of files and paths related to a play.
 :
 : @param $url DB URL to play TEI document
 : @return map()
 :)
declare function dutil:filepaths ($url as xs:string) as map() {
  let $segments := tokenize($url, "/")
  let $corpusname := $segments[last() - 1]
  let $filename := $segments[last()]
  let $playname := substring-before($filename, ".xml")
  return map {
    "filename": $filename,
    "playname": $playname,
    "corpusname": $corpusname,
    "collections": map {
      "tei": $config:data-root || "/" || $corpusname,
      "metrics": $config:metrics-root || "/" || $corpusname,
      "rdf": $config:rdf-root || "/" || $corpusname
    },
    "files": map {
      "tei": $config:data-root || "/" || $corpusname || "/" || $filename,
      "metrics": $config:metrics-root || "/" || $corpusname || "/" || $filename,
      "rdf": $config:rdf-root || "/" || $corpusname || "/" || $playname
        || ".rdf.xml"
    },
    "url": $url
  }
};

(:~
 : Provide map of files and paths related to a play.
 :
 : @param $corpusname
 : @param $playname
 : @return map()
 :)
declare function dutil:filepaths (
  $corpusname as xs:string,
  $playname as xs:string
) as map() {
  let $filename := $playname || ".xml"
  return map {
    "filename": $filename,
    "playname": $playname,
    "corpusname": $corpusname,
    "collections": map {
      "tei": $config:data-root || "/" || $corpusname,
      "metrics": $config:metrics-root || "/" || $corpusname,
      "rdf": $config:rdf-root || "/" || $corpusname,
      "sitelinks": $config:sitelinks-root || "/" || $corpusname
    },
    "files": map {
      "tei": $config:data-root || "/" || $corpusname || "/" || $filename,
      "metrics": $config:metrics-root || "/" || $corpusname || "/" || $filename,
      "rdf": $config:rdf-root || "/" || $corpusname || "/" || $playname
        || ".rdf.xml"
    },
    "url": $config:data-root || "/" || $corpusname || "/" || $filename
  }
};

(:~
 : Return document for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:get-doc(
  $corpusname as xs:string,
  $playname as xs:string
) as node()* {
  let $doc := doc(
    $config:data-root || "/" || $corpusname || "/" || $playname || ".xml"
  )
  return $doc
};

(:~
 : Return DraCor ID of a play.
 :
 : @param $tei TEI document
 :)
declare function dutil:get-dracor-id($tei as element(tei:TEI)) as xs:string* {
  $tei/@xml:id/string()
};

(:~
 : Retrieve the speaker children of a given element and return the distinct IDs
 : referenced in @who attributes of those elements.
 :)
declare function dutil:distinct-speakers ($parent as element()*) as item()* {
    let $whos :=
      for $w in $parent//tei:sp/@who
      return tokenize(normalize-space($w), '\s+')
    for $ref in distinct-values($whos)
    (: catch invalid references :)
    (: (see https://github.com/dracor-org/gerdracor/issues/6) :)
    where string-length($ref) > 1
    return substring($ref, 2)
};

(:~
 : Retrieve and filter spoken text
 :
 : This function selects the `tei:p` and `tei:l` elements inside the `tei:sp`
 : descendants of a given element $parent and strips them of possible stage
 : directions (`tei:stage`). Optionally the `sp` elements can be limited to
 : those referencing the ID $speaker in their @who attribute.
 :
 : @param $parent Element to search in
 : @param $speaker Speaker ID
 :)
declare function dutil:get-speech (
  $parent as element(),
  $speaker as xs:string?
) as item()* {
  let $lines := $parent//tei:sp[not($speaker) or tokenize(@who)='#'||$speaker]
                //(tei:p|tei:l)
  return functx:remove-elements-deep($lines, ('*:stage', '*:note'))
};

(:~
 : Retrieve and filter spoken text by gender
 :
 : This function selects the `tei:p` and `tei:l` elements inside those `tei:sp`
 : descendants of a given element $parent that reference a speaker with the
 : given gender. It then strips these elements possible stage directions
 : (`tei:stage`).
 :
 : @param $parent Element to search in
 : @param $gender Gender of speaker
 :)
declare function dutil:get-speech-by-gender (
  $parent as element(),
  $gender as xs:string+
) as item()* {
  let $ids := $parent/ancestor::tei:TEI//tei:particDesc
              /tei:listPerson/(tei:person|tei:personGrp)[@sex = $gender]
              /@xml:id/string()
  let $refs := for $id in $ids return '#'||$id
  let $sp := $parent//tei:sp[@who = $refs]//(tei:p|tei:l)
  return functx:remove-elements-deep($sp, ('*:stage', '*:note'))
};

(:~
 : Retrieve and filter spoken text by gender and/or relation
 :
 : This function selects the `tei:p` and `tei:l` elements inside those `tei:sp`
 : descendants of a given element $parent that reference a speaker with the
 : given gender and/or relation. It then strips these elements possible stage
 : directions (`tei:stage`).
 :
 : Possible values for the relation parameter are:
 :  - siblings
 :  - friends
 :  - spouses
 :  - parent_of_active
 :  - lover_of_active
 :  - related_with_active
 :  - associated_with_active
 :  - parent_of_passive
 :  - lover_of_passive
 :  - related_with_passive
 :  - associated_with_passive
 :
 : @param $parent Element to search in
 : @param $gender Gender of speaker
 : @param $relation Relation of speaker.
 :)
declare function dutil:get-speech-filtered (
  $parent as element(),
  $gender as xs:string*,
  $relation as xs:string*,
  $role as xs:string*
) as item()* {
  let $undirected := ("siblings", "friends", "spouses")
  let $directed := ("parent_of", "lover_of", "related_with", "associated_with")
  let $active := for $x in $directed return $x || '_active'
  let $passive := for $x in $directed return $x || '_passive'
  let $rel := replace($relation, '_(active|passive)$', '')
  let $genders := tokenize($gender, ',')
  let $roles := tokenize($role, ',')

  let $listPerson := $parent/ancestor::tei:TEI//tei:particDesc/tei:listPerson
  let $relations := $listPerson/tei:listRelation[@type="personal"]

  let $ids := $listPerson/(tei:person|tei:personGrp)
    [
      (not($gender) or @sex = $genders) and
      (not($role) or tokenize(@role, '\s+') = $roles)
    ]/@xml:id/string()

  let $filtered := for $id in $ids
    return if (not($relation)) then
      $id
    else if (
      $relation = $undirected
      and $relations/tei:relation
        [@name = $relation and contains(@mutual||' ', '#'||$id||' ')]
    ) then
      $id
    else if (
      $relation = $active
      and $relations/tei:relation
        [@name = $rel and contains(@active||' ', '#'||$id||' ')]
    ) then
      $id
    else if (
      $relation = $passive
      and $relations/tei:relation
        [@name = $rel and contains(@passive||' ', '#'||$id||' ')]
    ) then
      $id
    else ()

  let $refs := for $id in $filtered return '#'||$id
  let $sp := $parent//tei:sp[@who = $refs]//(tei:p|tei:l)
  return functx:remove-elements-deep($sp, ('*:stage', '*:note'))
};

(:~
 : Count words in spoken text, optionally limited to the speaker identified by
 : ID $speaker referenced in @who attributes of `tei:sp` elements.
 :
 : If this function detects any `tei:w` descendants inside `tei:sp` elements,
 : it will use those to determine the number of spoken words. Otherwise the word
 : count will be based on tokenization by subsequent non-word characters
 : (`\W+`).
 :
 : @param $parent Element to search in
 : @param $speaker Speaker ID
 :)
declare function dutil:num-of-spoken-words (
  $parent as element(),
  $speaker as xs:string?
) as item()* {
  if($parent//tei:sp//tei:w) then
    let $words := $parent//tei:sp[not($speaker) or tokenize(@who)='#'||$speaker]
                  //(tei:l|tei:p)//tei:w[not(ancestor::tei:stage)]
    return count($words)
  else
    let $sp := dutil:get-speech($parent, $speaker)
    let $txt := string-join($sp/normalize-space(), ' ')
    return count(tokenize($txt, '\W+')[not(.='')])
};

(:~
 : Retrieve `div` elements considered a segment. These are usually `div`s
 : containing `sp` elements. However, also included are 'empty' scenes with no
 : speakers, e.g. those consisting only of stage directions.
 :
 : @param $tei The TEI root element of a play
 :)
declare function dutil:get-segments ($tei as element()*) as element()* {
  if(not($tei//tei:body//(tei:div|tei:div1))) then
    (: missing segmentation :)
    $tei//tei:body
  else if($tei//tei:body//tei:div2[@type="scene"]) then
    (: romdracor :)
    (: plautus-trinummus has the prologue coded as div1 which is why we
     : recognize div1 without div2 children as segment
     :)
    $tei//tei:body//(tei:div2[@type="scene"]|tei:div1[tei:sp and not(tei:div2)])
  else if ($tei//tei:body//tei:div1) then
    (: greekdracor :)
    $tei//tei:body//tei:div1
  else
    (: for all others we rely on divs having sp children :)
    $tei//tei:body//tei:div[tei:sp or (@type="scene" and not(.//tei:sp))]
};

declare function local:get-year($iso-date as xs:string) as xs:string* {
  let $parts := tokenize($iso-date, "-")
  (:
    When the first part after tokenizing is empty we have a negative, i.e. BCE,
    year and prepend it with "-". Otherwise we consider the first part a CE
    year.
  :)
  return if ($parts[1] eq "") then "-" || $parts[2] else $parts[1]
};

(:~
 : Retrieve `written`, `premiere` and `print` years as ISO 8601 strings for the
 : play passed in $tei.
 :
 : @param $tei The TEI root element of a play
 : @return Map of years
 :)
declare function dutil:get-years-iso ($tei as element(tei:TEI)*) as map(*) {
  let $dates := $tei//tei:standOff/tei:listEvent/tei:event
    [@type = ("print", "premiere", "written")]
    [@when or @notAfter or @notBefore]

  let $years := map:merge(
    for $d in $dates
    let $type := $d/@type/string()
    let $year := if ($d/@when) then
      local:get-year($d/@when/string())
    else if ($d/@notBefore and $d/@notAfter) then
      local:get-year($d/@notBefore/string()) ||
      '/' ||
      local:get-year($d/@notAfter/string())
    else if ($d/@notAfter) then
      '<' || local:get-year($d/@notAfter/string())
    else
      '>' || local:get-year($d/@notBefore/string())
    return map:entry($type, $year)
  )

  return $years
};

(:~
 : Retrieve `written`, `premiere` and `print` years for the play passed in $tei.
 :
 : @param $tei The TEI root element of a play
 : @return Map of years
 :)
declare function dutil:get-years ($tei as element(tei:TEI)*) as map(*) {
  let $dates := $tei//tei:standOff/tei:listEvent/tei:event
    [@type = ("print", "premiere", "written")]
    [@when or @notAfter or @notBefore]

  let $years := map:merge(
    for $d in $dates
    let $type := $d/@type/string()

    let $date := if ($d/@when) then
      $d/@when/string()
    else if ($d/@notAfter) then
      $d/@notAfter/string()
    else
      $d/@notBefore/string()

    let $year := if(matches($date, "^[0-9]{4}")) then
      substring($date, 1, 4)
    else if (matches($date, "^-[0-9]{4}")) then
      substring($date, 1, 5)
    else ()

    return if ($year) then map:entry($type, $year) else ()
  )

  return $years
};

(:~
 : Retrieve premiere date for the play passed in $tei.
 :
 : This function only returns a value when the exact date of the premiere in ISO
 : format (YYYY-MM-DD) is specified in tei:standOff.
 :
 : @param $tei The TEI root element of a play
 : @return ISO date string
 :)
declare function dutil:get-premiere-date ($tei as element(tei:TEI)*) as xs:string* {
  let $date := $tei//tei:standOff/tei:listEvent/tei:event
    [@type = "premiere"]/@when
  return if (matches($date, "^-?[0-9]{4}-[0-9]{2}-[0-9]{2}")) then $date else ()
};

(:~
 : Determine the most fitting year from `written`, `premiere` and `print` of
 : the play passed in $tei.
 :
 : @param $tei The TEI root element of a play
 :)
declare function dutil:get-normalized-year (
  $tei as element(tei:TEI)*
) as xs:integer* {
  let $years := dutil:get-years($tei)

  let $written := $years?written
  let $premiere := $years?premiere
  let $print := $years?print

  let $published := if ($print and $premiere)
    then (
      if (xs:integer($premiere) < xs:integer($print))
      then $premiere
      else $print
    )
    else if ($premiere) then $premiere
    else $print

  let $year := if ($written and $published)
    then
      if (xs:integer($published) - xs:integer($written) > 10)
      then $written
      else $published
    else if ($written) then $written
    else $published

  return xs:integer($year)
};

(:~
 : Count number of site links for play identified by $wikidata-id.
 :
 : @param $wikidata-id
 :)
declare function dutil:count-sitelinks(
  $wikidata-id as xs:string*,
  $corpusname as xs:string
) {
  let $col := concat($config:sitelinks-root, "/", $corpusname)
  return if($wikidata-id) then
    count(collection($col)/sitelinks[@id=$wikidata-id]/uri)
  else ()
};

(:~
 : Get teiCorpus element for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return teiCorpus element
 :)
declare function dutil:get-corpus(
  $corpusname as xs:string
) as element()* {
  collection($config:data-root)//tei:teiCorpus[
    tei:teiHeader//tei:publicationStmt/tei:idno[
      @type="URI" and
      @xml:base="https://dracor.org/" and
      . = $corpusname
    ]
  ]
};

declare function local:to-markdown($input as element()) as item()* {
  for $child in $input/node()
  return
    if ($child instance of element())
    then (
      if (name($child) = 'ref')
      then "[" || $child/text() || "](" || $child/@target || ")"
      else if (name($child) = 'hi')
      then "**" || $child/text() || "**"
      else local:to-markdown($child)
    )
    else $child
};
declare function local:markdown($input as element()) as item()* {
  normalize-space(string-join(local:to-markdown($input), ''))
};

(:~
 : Get basic information for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return map
 :)
declare function dutil:get-corpus-info(
  $corpus as element(tei:teiCorpus)*
) as map(*)* {
  let $header := $corpus/tei:teiHeader
  let $name := $header//tei:publicationStmt/tei:idno[
    @type="URI" and @xml:base="https://dracor.org/"
  ]/text()
  let $title := $header/tei:fileDesc/tei:titleStmt/tei:title[1]/text()
  let $acronym := $header/tei:fileDesc/tei:titleStmt/tei:title[@type="acronym"]/text()
  let $repo := $header//tei:publicationStmt/tei:idno[@type="repo"]/text()
  let $projectDesc := $header/tei:encodingDesc/tei:projectDesc
  let $licence := $header//tei:availability/tei:licence
  let $description := if ($projectDesc) then (
    let $paras := for $p in $projectDesc/tei:p return local:markdown($p)
    return string-join($paras, "&#10;&#10;")
  ) else ()
  return if ($header) then (
    map:merge((
      map:entry("name", $name),
      map:entry("title", $title),
      map:entry(
        "acronym",
        if ($acronym)
          then $acronym
          else (functx:capitalize-first($name) || "DraCor")
      ),
      if ($repo) then map:entry("repository", $repo) else (),
      if ($description) then map:entry("description", $description) else (),
      if ($licence)
        then map:entry("licence", normalize-space($licence)) else (),
      if ($licence/@target)
        then map:entry("licenceUrl", $licence/@target/string()) else ()
    ))
  ) else ()
};

(:~
 : Get basic information for corpus identified by $corpusname.
 :
 : @param $corpusname
 : @return map
 :)
declare function dutil:get-corpus-info-by-name(
  $corpusname as xs:string
) as map(*)* {
  let $corpus := dutil:get-corpus($corpusname)
  return dutil:get-corpus-info($corpus)
};

(:~
 : Extract text class information from TEI document.
 :
 : See https://github.com/dracor-org/dracor-api/issues/120
 :
 : @param $tei
 : @return sequence of strings (see $config:wd-text-classes for possible values)
 :)
declare function dutil:get-text-classes($tei as node()) as xs:string* {
  for $id in $tei//tei:textClass
    /tei:classCode[@scheme="http://www.wikidata.org/entity/"]/string()
  where map:contains($config:wd-text-classes, $id)
  return $config:wd-text-classes($id)
};

(:~
 : Determine genre from text classes.
 :
 : @param $text-classes
 : @return string
 :)
declare function dutil:get-genre($text-classes as xs:string*) as xs:string? {
  (: return the first non-libretto text class if any :)
  if($text-classes[1] = 'Libretto') then $text-classes[2] else $text-classes[1]
};

(:~
 : Calculate meta data for corpus.
 :
 : @param $corpusname
 : @return sequence of maps
 :)
declare function dutil:get-corpus-meta-data(
  $corpusname as xs:string
) as map(*)* {
  let $metrics-collection := concat($config:metrics-root, "/", $corpusname)
  let $metrics := for $s in collection($metrics-collection)//metrics
    let $uri := base-uri($s)
    let $fname := tokenize($uri, "/")[last()]
    let $name := tokenize($fname, "\.")[1]
    return <metrics name="{$name}">{$s/*}</metrics>
  (: return $metrics :)
  let $collection := concat($config:data-root, "/", $corpusname)

  for $tei in collection($collection)//tei:TEI
  let $filename := tokenize(base-uri($tei), "/")[last()]
  let $id := dutil:get-dracor-id($tei)
  let $name := tokenize($filename, "\.")[1]
  let $years := dutil:get-years-iso($tei)
  let $authors := dutil:get-authors($tei)
  let $titles := dutil:get-titles($tei)

  let $text-classes := dutil:get-text-classes($tei)

  let $num-speakers := count(dutil:distinct-speakers($tei))

  let $characters := $tei//tei:particDesc/tei:listPerson/(tei:person|tei:personGrp)
  let $num-male := count($characters[@sex="MALE"])
  let $num-female := count($characters[@sex="FEMALE"])
  let $num-unknown := count($characters[@sex="UNKNOWN"])
  let $num-groups := count($characters[name()="personGrp"])

  let $num-p := count($tei//tei:body//tei:sp//tei:p)
  let $num-l := count($tei//tei:body//tei:sp//tei:l)

  let $stat := $metrics[@name=$name]
  let $max-degree-ids := tokenize($stat/network/maxDegreeIds)
  let $wikidata-id := dutil:get-play-wikidata-id($tei)
  let $sitelink-count := dutil:count-sitelinks($wikidata-id, $corpusname)

  let $networkmetrics := map:merge(
    for $s in $stat/network/*[not(name() = ("maxDegreeIds", "nodes"))]
    let $v := $s/text()
    return map:entry(
      $s/name(),
      if(xs:string(number($v)) != "NaN") then number($v) else $v
    )
  )

  let $digitalSource := $tei//tei:sourceDesc/
    tei:bibl[@type="digitalSource"]/tei:idno[@type="URL"][1]/text()

  let $origSource := $tei//tei:sourceDesc//
    tei:bibl[@type="originalSource"][1]
  let $origSourcePublisher := normalize-space($origSource/tei:publisher)
  let $origSourcePubPlace := string-join(
    $origSource/tei:pubPlace ! normalize-space(), ", "
  )
  let $year := $origSource/tei:date
  let $origSourceYear := if (number($year)) then xs:integer($year) else ()
  let $scope := $origSource/tei:biblScope[@unit="page" and @from and @to]
  let $origSourceNumPages :=
    if ($scope and number($scope/@to) and number($scope/@from))
    then number($scope/@to) - number($scope/@from) + 1
    else ()


  let $meta := map {
    "id": $id,
    "name": $name,
    "wikidataId": $wikidata-id,
    "normalizedGenre": dutil:get-genre($text-classes),
    "libretto": $text-classes = 'Libretto',
    "firstAuthor": $authors[1]?shortname,
    "title": $titles?main,
    "subtitle": if ($titles?sub) then $titles?sub else (),
    "numOfCoAuthors": if(count($authors) > 0) then count($authors) - 1 else 0,
    "maxDegreeIds": if(count($max-degree-ids) < 4) then
      string-join($max-degree-ids, "|")
    else
      "several characters",
    "numOfSegments": count(dutil:get-segments($tei)),
    "numOfActs": count($tei//tei:div[@type="act"]),
    "numOfSpeakers": $num-speakers,
    "numOfSpeakersMale": $num-male,
    "numOfSpeakersFemale": $num-female,
    "numOfSpeakersUnknown": $num-unknown,
    "numOfPersonGroups": $num-groups,
    "numOfP": $num-p,
    "numOfL": $num-l,
    "wikipediaLinkCount": $sitelink-count,
    "wordCountText": xs:integer($stat/text/string()),
    "wordCountSp": xs:integer($stat/sp/string()),
    "wordCountStage": xs:integer($stat/stage/string()),
    "datePremiered": dutil:get-premiere-date($tei),
    "yearWritten": $years?written,
    "yearPremiered": $years?premiere,
    "yearPrinted": $years?print,
    "yearNormalized": xs:integer(dutil:get-normalized-year($tei)),
    "digitalSource": $digitalSource,
    "originalSourcePublisher": if ($origSourcePublisher) then
      $origSourcePublisher else (),
    "originalSourcePubPlace": if ($origSourcePubPlace) then
      $origSourcePubPlace else (),
    "originalSourceYear": $origSourceYear,
    "originalSourceNumberOfPages": $origSourceNumPages
  }
  order by $filename
  return map:merge(($meta, $networkmetrics))
};

(:~
 : Extract full name from author element.
 :
 : @param $author author element
 : @return string
 :)
declare function dutil:get-full-name ($author as element(tei:author)) {
  if ($author/tei:persName) then
    normalize-space($author/tei:persName[1])
  else if ($author/tei:name) then
    normalize-space($author/tei:name[1])
  else normalize-space($author)
};

(:~
 : Extract full name from author element by language.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function dutil:get-full-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  if ($author/tei:persName[@xml:lang=$lang]) then
    normalize-space($author/tei:persName[@xml:lang=$lang][1])
  else if ($author/tei:name[@xml:lang=$lang]) then
    normalize-space($author/tei:name[@xml:lang=$lang][1])
  else ()
};

declare function local:build-short-name ($name as element()) {
  if ($name/tei:surname) then
    let $n := if ($name/tei:surname[@sort="1"]) then
      $name/tei:surname[@sort="1"] else $name/tei:surname[1]
    return normalize-space($n)
  else normalize-space($name)
};

(:~
 : Extract short name from author element.
 :
 : @param $author author element
 : @return string
 :)
declare function dutil:get-short-name ($author as element(tei:author)) {
  let $name := if ($author/tei:persName) then
    $author/tei:persName[1]
  else if ($author/tei:name) then
    $author/tei:name[1]
  else ()

  return if (not($name)) then
    normalize-space($author)
  else local:build-short-name($name)
};

(:~
 : Extract short name from author element by language.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function dutil:get-short-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  let $name := if ($author/tei:persName[@xml:lang=$lang]) then
    $author/tei:persName[@xml:lang=$lang][1]
  else if ($author/tei:name[@xml:lang=$lang]) then
    $author/tei:name[@xml:lang=$lang][1]
  else ()

  return if (not($name)) then () else local:build-short-name($name)
};

declare function local:build-sort-name ($name as element()) {
  (:
   : If there is a surname and it is not the first element in the name we
   : rearrange the name to put it first. Otherwise we just return the normalized
   : text as written in the document.
   :)
  if ($name/tei:surname and not($name/tei:*[1] = $name/tei:surname)) then
    let $start := if ($name/tei:surname[@sort="1"]) then
      $name/tei:surname[@sort="1"] else $name/tei:surname[1]

    return string-join(
      ($start, $start/(following-sibling::text()|following-sibling::*)), ""
    ) => normalize-space()
    || ", "
    || string-join(
      $start/(preceding-sibling::text()|preceding-sibling::*), ""
    ) => normalize-space()
  else normalize-space($name)
};

(:~
 : Extract name from author element that is suitable for sorting.
 :
 : @param $author author element
 : @return string
 :)
declare function dutil:get-sort-name ($author as element(tei:author) ) {
  let $name := if ($author/tei:persName) then
    $author/tei:persName[1]
  else if ($author/tei:name) then
    $author/tei:name[1]
  else ()

  return if (not($name)) then
    normalize-space($author)
  else local:build-sort-name($name)
};

(:~
 : Extract name by language from author element that is suitable for sorting.
 :
 : @param $author author element
 : @param $lang language code
 : @return string
 :)
declare function dutil:get-sort-name (
  $author as element(tei:author),
  $lang as xs:string
) {
  let $name := if ($author/tei:persName[@xml:lang=$lang]) then
    $author/tei:persName[@xml:lang=$lang][1]
  else if ($author/tei:name[@xml:lang=$lang]) then
    $author/tei:name[@xml:lang=$lang][1]
  else ()

  return if (not($name)) then () else local:build-sort-name($name)
};

(:~
 : Retrieve author data from TEI.
 :
 : @param $tei
 :)
declare function dutil:get-authors($tei as node()) as map()* {
  for $author in $tei//tei:fileDesc/tei:titleStmt/tei:author[
    not(@role="illustrator")
  ]
  let $name := dutil:get-sort-name($author)
  let $fullname := dutil:get-full-name($author)
  let $shortname := dutil:get-short-name($author)
  let $nameEn := dutil:get-sort-name($author, 'eng')
  let $fullnameEn := dutil:get-full-name($author, 'eng')
  let $shortnameEn := dutil:get-short-name($author, 'eng')
  let $refs := array {
    for $idno in $author/tei:idno[@type]
    let $ref := $idno => normalize-space()
    let $type := string($idno/@type)
    return map {
      "ref": $ref,
      "type": $type
    }
  }
  let $aka := array {
    for $name in $author/tei:persName[position() > 1]
    return $name => normalize-space()
  }

  return map:merge((
    map {
      "name": $name,
      "fullname": $fullname,
      "shortname": $shortname,
      "refs": $refs
    },
    if ($nameEn) then map {"nameEn": $nameEn} else (),
    if ($fullnameEn) then map {"fullnameEn": $fullnameEn} else (),
    if ($shortnameEn) then map {"shortnameEn": $shortnameEn} else (),
    if (array:size($aka) > 0) then map {"alsoKnownAs": $aka} else ()
  ))
};

(:~
 : Retrieve title and subtitle from TEI.
 :
 : @param $tei
 :)
declare function dutil:get-titles(
  $tei as element(tei:TEI)
) as map() {
  let $title := $tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space()
  let $subtitle :=
    $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
  return map:merge((
    if ($title) then map {'main': $title} else (),
    if ($subtitle) then map {'sub': $subtitle} else ()
  ))
};

(:~
 : Retrieve title and subtitle from TEI by language.
 :
 : @param $tei
 : @param $lang
 :)
declare function dutil:get-titles(
  $tei as element(tei:TEI),
  $lang as xs:string
) as map() {
  if($lang = $tei/@xml:lang) then
    dutil:get-titles($tei)
  else
  let $title :=
    $tei//tei:fileDesc/tei:titleStmt
      /tei:title[@xml:lang = $lang and not(@type = 'sub')][1]
      /normalize-space()
  let $subtitle :=
    $tei//tei:titleStmt/tei:title[@type = 'sub' and @xml:lang = $lang][1]
      /normalize-space()
  return map:merge((
    if ($title) then map {'main': $title} else (),
    if ($subtitle) then map {'sub': $subtitle} else ()
  ))
};

(:~
 : Retrieve digital source from TEI document.
 :
 : @param $tei
 :)
declare function dutil:get-source($tei as element(tei:TEI)) as map()? {
  let $source := $tei//tei:sourceDesc/tei:bibl[@type="digitalSource"]
  return if (count($source)) then map:merge((
    if ($source/tei:name) then
      map {'name': $source/tei:name[1]/normalize-space()}
    else (),
    if ($source/tei:idno[@type="URL"]) then
      map {'url': $source/tei:idno[@type="URL"][1]/normalize-space()}
    else ()
  )) else ()
};

(:~
 : Extract Wikidata ID for play from standOff.
 :
 : @param $tei TEI element
 :)
declare function dutil:get-play-wikidata-id ($tei as element(tei:TEI)) {
  let $uri := $tei//tei:standOff/tei:listRelation
    /tei:relation[@name="wikidata"][1]/@passive/string()
  return if (starts-with($uri, 'http://www.wikidata.org/entity/')) then
    tokenize($uri, '/')[last()]
  else ()
};

(:~
 : Extract all Wikidata IDs for plays in a corpus.
 :
 : @param $corpus Corpus name
 :)
declare function dutil:get-play-wikidata-ids ($corpus as xs:string) {
  let $data-col := $config:data-root || '/' || $corpus
  for $uri in collection($data-col)
    /tei:TEI//tei:standOff/tei:listRelation
      /tei:relation[@name="wikidata"]/@passive/string()
  return if (starts-with($uri, 'http://www.wikidata.org/entity/')) then
    tokenize($uri, '/')[last()]
  else ()
};

(:~
 : Retrieve Wikidata ID from element with `ana` attribute.
 :
 : @param $e element with 'ana' attribute
 :
 : NB: we make the $e parameter optional to gracefully handle cases where no
 : `person` element is found in `particDesc` for a given speaker ID. We may
 : consider to change this after stricter schematron rules are in place. See
 : https://github.com/dracor-org/dracor-schema/issues/16#issuecomment-887005105.
 :)
declare function dutil:get-wikidata-id-from-ana(
  $e as element()?
) as xs:string* {
  if(starts-with($e/@ana, 'http://www.wikidata.org/entity/')) then
    substring($e/@ana, 32)
  else
    ()
};

(:~
 : Calculate meta data for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:get-play-info(
  $corpusname as xs:string,
  $playname as xs:string
) as map()? {
  let $doc := dutil:get-doc($corpusname, $playname)
  return if (not($doc)) then
    ()
  else
    let $tei := $doc//tei:TEI
    let $id := dutil:get-dracor-id($tei)
    let $uri :=
      $config:api-base || "/corpora/" || $corpusname || "/plays/" || $playname
    let $titles := dutil:get-titles($tei)
    let $titlesEn := dutil:get-titles($tei, 'eng')
    let $source := dutil:get-source($tei)
    let $orig-source := $tei//tei:bibl[@type="originalSource"][1]/normalize-space(.)
    let $speakers := dutil:distinct-speakers($doc//tei:body)
    let $lastone := $speakers[last()]

    let $segments := array {
      for $segment at $pos in dutil:get-segments($tei)
      let $heads :=
        $segment/(ancestor::tei:div/tei:head,tei:head)
          ! functx:remove-elements-deep(., ('*:note'))
          ! normalize-space(.)
      let $speakers := dutil:distinct-speakers($segment)
      return map:merge((
        map {
          "type": $segment/@type/string(),
          "number": $pos
        },
        if(count($heads)) then
          map {"title": string-join($heads, ' | ')}
        else (),
        if(count($speakers)) then map:entry(
          "speakers",
          array { for $sp in $speakers return $sp }
        ) else ()
      ))
    }

    let $authors := dutil:get-authors($tei)

    let $text-classes := dutil:get-text-classes($tei)

    let $years := dutil:get-years-iso($tei)
    let $premiere-date := dutil:get-premiere-date($tei)

    let $all-in-segment := $segments?*[?speakers=$lastone][1]?number
    let $all-in-index := $all-in-segment div count($segments?*)

    let $wikidata-id := dutil:get-play-wikidata-id($tei)

    let $relations := dutil:get-relations($corpusname, $playname)

    return map:merge((
      map {
        "id": $id,
        "uri": $uri,
        "name": $playname,
        "corpus": $corpusname,
        "title": $titles?main,
        "authors": array { for $author in $authors return $author },
        "normalizedGenre": dutil:get-genre($text-classes),
        "libretto": $text-classes = 'Libretto',
        "allInSegment": $all-in-segment,
        "allInIndex": $all-in-index,
        "characters": array {
          for $id in $speakers
          let $node := $doc//tei:particDesc//(
            tei:person[@xml:id=$id] | tei:personGrp[@xml:id=$id]
          )
          let $name := $node/(tei:persName | tei:name)[1]/text()
          let $sex := $node/@sex/string()
          let $isGroup := if ($node/name() eq 'personGrp')
            then true() else false()
          let $wikidata-id := dutil:get-wikidata-id-from-ana($node)
          return map:merge((
            map {
              "id": $id,
              "name": $name,
              "isGroup": $isGroup,
              "sex": if($sex) then $sex else ()
            },
            if ($wikidata-id) then map:entry("wikidataId", $wikidata-id) else ()
          ))
        },
        "segments": $segments,
        "yearWritten": $years?written,
        "yearPremiered": $years?premiere,
        "yearPrinted": $years?print,
        "yearNormalized": xs:integer(dutil:get-normalized-year($tei))
      },
      if($titlesEn?main) then map:entry("titleEn", $titlesEn?main) else (),
      if($titles?sub) then map:entry("subtitle", $titles?sub) else (),
      if($titlesEn?sub) then map:entry("subtitleEn", $titlesEn?sub) else (),
      if($wikidata-id) then
        map:entry("wikidataId", $wikidata-id)
      else (),
      if($orig-source) then
        map:entry("originalSource", $orig-source)
      else (),
      if(count($source)) then map:entry("source", $source) else (),
      if($premiere-date) then map:entry("datePremiered", $premiere-date) else (),
      if(count($relations)) then
        map:entry("relations", array{$relations})
      else ()
    ))
};

(:~
 : Retrieve metrics data for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:get-play-metrics(
  $corpusname as xs:string,
  $playname as xs:string
)  {
  let $doc := dutil:get-doc($corpusname, $playname)
  return if (not($doc)) then
    ()
  else
    let $tei := $doc//tei:TEI
    let $paths := dutil:filepaths($corpusname, $playname)
    let $metrics := doc($paths?files?metrics)//metrics

    let $id := dutil:get-dracor-id($tei)
    let $wikidata-id := dutil:get-play-wikidata-id($tei)
    let $sitelink-count := dutil:count-sitelinks($wikidata-id, $corpusname)

    let $nodes := array {
      for $n in $metrics/network/nodes/node
      return map:merge((
        map:entry("id", $n/@id/string()),
        for $s in $n/*
        let $v := $s/text()
        return map:entry(
          $s/name(),
          if(xs:string(number($v)) != "NaN") then number($v) else $v
        )
      ))
    }

    let $meta := map {
      "id": $id,
      "name": $playname,
      "corpus": $corpusname,
      "wikipediaLinkCount": $sitelink-count,
      "nodes": $nodes
    }

    let $networkmetrics := map:merge(
      for $e in $metrics/network/*[not(name() = "nodes")]
      let $v := if($e/name() = "maxDegreeIds") then
        array {tokenize($e)}
      else
        $e/text()
      return map:entry(
        $e/name(),
        if(xs:string(number($v)) != "NaN") then number($v) else $v
      )
    )

    return map:merge(($meta, $networkmetrics))
};

(:~
 : Compile info about characters of a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:characters-info (
  $corpusname as xs:string,
  $playname as xs:string
) as item()? {
  let $doc := dutil:get-doc($corpusname, $playname)
  return if (not($doc)) then
    ()
  else
    let $tei := $doc//tei:TEI
    let $speakers := dutil:distinct-speakers($doc//tei:body)

    let $segments := array {
      for $segment at $pos in dutil:get-segments($tei)
      return map {
        "number": $pos,
        "speakers": array {
          for $sp in dutil:distinct-speakers($segment) return $sp
        }
      }
    }

    let $metrics := doc(dutil:filepaths($corpusname, $playname)?files?metrics)

    return array {
      for $id in $speakers
      let $node := $doc//tei:particDesc//(
        tei:person[@xml:id=$id] | tei:personGrp[@xml:id=$id]
      )
      let $name := $node/(tei:persName | tei:name)[1]/text()
      let $sex := $node/@sex/string()
      let $isGroup := if ($node/name() eq 'personGrp')
        then true() else false()
      let $num-of-speech := $tei//tei:sp[@who='#'||$id]
      let $metrics-node := $metrics//node[@id=$id]
      let $eigenvector := if ($metrics-node/eigenvector) then
        number($metrics-node/eigenvector) else 0
      let $wikidata-id := dutil:get-wikidata-id-from-ana($node)
      return map:merge((
        map {
          "id": $id,
          "name": $name,
          "isGroup": $isGroup,
          "gender": if($sex) then $sex else (),
          "numOfScenes": count($segments?*[?speakers = $id]),
          "numOfSpeechActs": count($tei//tei:sp[@who = '#'||$id]),
          "numOfWords": dutil:num-of-spoken-words($tei, $id),
          "degree": $metrics-node/degree/xs:integer(.),
          "weightedDegree": if ($metrics-node/weightedDegree) then
            $metrics-node/weightedDegree/xs:integer(.) else 0,
          "closeness": $metrics-node/closeness/number(.),
          "betweenness": $metrics-node/betweenness/number(.),
          "eigenvector": $eigenvector
        },
        if ($wikidata-id) then map:entry("wikidataId", $wikidata-id) else ()
      ))
    }
};

declare function local:tokenize($idrefs as node()) as item()* {
  for $ref in normalize-space($idrefs) => tokenize('\s+') => distinct-values()
  where string-length($ref) > 1
  return substring($ref, 2)
};

(:~
 : Extract relations for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:get-relations (
  $corpusname as xs:string,
  $playname as xs:string
) as map()* {
  let $doc := dutil:get-doc($corpusname, $playname)
  let $listRel := $doc//tei:listRelation[@type = "personal"]
  let $relations := (
    for $rel in $listRel/tei:relation[@mutual]
      let $ids := local:tokenize($rel/@mutual)
      for $source at $pos in $ids
        for $target in $ids
        where index-of($ids, $target) gt $pos
        return map {
          "directed": false(),
          "type": string($rel/@name),
          "source": $source,
          "target": $target
        }
  ,
    for $rel in $listRel/tei:relation[@active]
      for $source in local:tokenize($rel/@active)
         for  $target in local:tokenize($rel/@passive)
         return map {
           "directed": true(),
           "type": string($rel/@name),
           "source": $source,
           "target": $target
         }
  )
  return $relations
};

(:~
 : Get info for plays having a character identified by Wikidata ID.
 :
 : @param $id Wikidata ID
 :)
declare function dutil:get-plays-with-character ($id as xs:string) {
  let $wd-uri := "http://www.wikidata.org/entity/" || $id
  let $plays := collection($config:data-root)
    /tei:TEI[.//tei:person[@ana=$wd-uri]]
  return array {
    for $tei in $plays
    let $id := dutil:get-dracor-id($tei)
    let $titles := dutil:get-titles($tei)
    let $authors := dutil:get-authors($tei)
    return map {
      "id": $id,
      "uri": "https://dracor.org/id/" || $id,
      "title": $titles?main,
      "authors": array { for $author in $authors return $author?fullname },
      "characterName": normalize-space(
        $tei//tei:particDesc/tei:listPerson/tei:person[@ana=$wd-uri]/tei:persName[1]
      )
    }
  }
};

(:~
 : Escape string for use in CSV
 :
 : @param $string
 :)
declare function dutil:csv-escape($string as xs:string) as xs:string {
  replace($string, '"', '""')
  (: replace($string, '\(', '((') :)
};

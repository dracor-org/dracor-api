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
declare namespace transform = "http://exist-db.org/xquery/transform";

(:~
 : Provide map of files and paths related to a play.
 :
 : @param $url DB URL to play TEI document
 : @return map()
 :)
declare function dutil:filepaths ($url as xs:string) as map() {
  let $segments := tokenize($url, "/")
  let $corpusname := $segments[last() - 2]
  let $playname := $segments[last() - 1]
  let $filename := $segments[last()]
  return dutil:filepaths($corpusname, $playname, $filename)
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
  dutil:filepaths($corpusname, $playname, "tei.xml")
};

(:~
 : Provide map of files and paths related to a play.
 :
 : @param $corpusname
 : @param $playname
 : @param $filename
 : @return map()
 :)
declare function dutil:filepaths (
  $corpusname as xs:string,
  $playname as xs:string,
  $filename as xs:string
) as map() {
  let $playpath := $config:corpora-root || "/" || $corpusname || "/" || $playname
  let $url := $playpath || "/" || $filename
  let $uri :=
    $config:api-base || "/corpora/" || $corpusname || "/plays/" || $playname
  return map {
    "uri": $uri,
    "url": $url,
    "filename": $filename,
    "playname": $playname,
    "corpusname": $corpusname,
    "collections": map {
      "corpus": $config:corpora-root || "/" || $corpusname,
      "play": $playpath
    },
    "files": map {
      "tei": $playpath || "/tei.xml",
      "metrics": $playpath || "/metrics.xml",
      "rdf": $playpath || "/rdf.xml",
      "git": $playpath || "/git.xml",
      "sitelinks": $playpath || "/sitelinks.xml"
    }
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
  let $paths := dutil:filepaths($corpusname, $playname)
  return doc($paths?files?tei)
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
 : Retrieve list of speaker IDs of a play filtered by gender, role or relation
 :
 : This function retrieve a list of IDs from the particDesc of a play that
 : can be filtered by gender, role and/or relation.
 :
 : The $relation parameter should be a value used in the `name` attribute of
 : the tei:listRelation/tei:relation element. For directed relations the active
 : or passive side can be selected using the $relation-role parameter.
 :
 : To support the behavior in API versions prior to 1.1.0 the relation role can
 : also be specified by suffixing the relation name with '_active' or
 : '_passive'. The $relation-role parameter, when used together with a suffix,
 : will have precedence.
 :
 : @param $tei Document element
 : @param $gender Gender of speaker
 : @param $role Role of speaker.
 : @param $relation Relation of speakers (mutual participants).
 : @param $relation-active Relation of speakers (active participants).
 : @param $relation-passive Relation of speakers (passive participants).
 :)
declare function dutil:get-filtered-speakers (
  $tei as element(tei:TEI),
  $gender as xs:string*,
  $role as xs:string*,
  $relation as xs:string*,
  $relation-active as xs:string*,
  $relation-passive as xs:string*
) as xs:string* {
  let $genders := tokenize($gender, ',')
  let $roles := tokenize($role, ',')

  (: extract possible relation role from $relation :)
  let $ana := analyze-string($relation, "_(active|passive)$")
  let $rel := $ana//fn:non-match/text()
  let $suffix := $ana//fn:group[@nr="1"]/text()

  let $mutual := if (not($suffix)) then $rel else ()
  let $active := if ($relation-active) then $relation-active else
    if ($suffix eq 'active') then $rel else ()
  let $passive := if ($relation-passive) then $relation-passive else
    if ($suffix eq 'passive') then $rel else ()

  let $listPerson := $tei//tei:particDesc/tei:listPerson
  let $relations := $listPerson/tei:listRelation
  let $ids := $listPerson/(tei:person|tei:personGrp)
    [
      (not($gender) or @sex = $genders) and
      (not($role) or tokenize(@role, '\s+') = $roles)
    ]/@xml:id/string()

  let $filtered := for $id in $ids
    return if (not($mutual) and not($active) and not($passive)) then
      $id
    else if (
      $relations/tei:relation
        [
          (@name = $mutual and contains(@mutual||' ', '#'||$id||' ')) or
          (@name = $active and contains(@active||' ', '#'||$id||' ')) or
          (@name = $passive and contains(@passive||' ', '#'||$id||' '))
        ]
    ) then
      $id
    else ()

  return $filtered
};

(:~
 : Extract plain text from document or element.
 :
 : @param $node element
 : @return Plain text content
 :)
declare function dutil:extract-text($node as node()) as xs:string {
  let $xsl := doc("/db/apps/dracor-v1/tei-to-txt.xsl")
  let $text := transform:transform($node, $xsl, ())
  (: trim leading spaces :)
  return replace($text, '\n +', '&#10;') => replace('^\s+', '')
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
 : Retrieve and filter spoken text by sex
 :
 : This function selects the `tei:p` and `tei:l` elements inside those `tei:sp`
 : descendants of a given element $parent that reference a speaker with the
 : given sex. It then strips these elements possible stage directions
 : (`tei:stage`).
 :
 : @param $parent Element to search in
 : @param $sex Sex of speaker
 :)
declare function dutil:get-speech-by-sex (
  $parent as element(),
  $sex as xs:string+
) as item()* {
  let $ids := $parent/ancestor::tei:TEI//tei:particDesc
              /tei:listPerson/(tei:person|tei:personGrp)[@sex = $sex]
              /@xml:id/string()
  let $refs := for $id in $ids return '#'||$id
  let $sp := $parent//tei:sp[@who = $refs]//(tei:p|tei:l)
  return functx:remove-elements-deep($sp, ('*:stage', '*:note'))
};

(:~
 : Retrieve and filter spoken text by sex, role and/or relation
 :
 : This function selects the `tei:p` and `tei:l` elements inside those `tei:sp`
 : descendants of a given element $parent that reference a speaker with the
 : given sex, role and/or relation. It then strips these elements of possible
 : stage directions and notes (`tei:stage`, `tei:note`).
 :
 : For the relation parameter also see dutil:get-filtered-speakers().
 :
 : @param $parent Element to search in
 : @param $sex Sex of speaker
 : @param $role Role of speaker
 : @param $relation Relation of speakers
 : @param $relation-active Relation of speakers (active participants)
 : @param $relation-passive Relation of speakers (passive participants)
 :)
declare function dutil:get-speech-filtered (
  $parent as element(),
  $sex as xs:string*,
  $role as xs:string*,
  $relation as xs:string*,
  $relation-active as xs:string*,
  $relation-passive as xs:string*
) as item()* {
  let $speakers := dutil:get-filtered-speakers(
    $parent/ancestor::tei:TEI, $sex, $role, $relation, $relation-active,
    $relation-passive
  )

  let $refs := for $id in $speakers return '#'||$id
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
  let $col := concat($config:corpora-root, "/", $corpusname)
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
  collection($config:corpora-root)//tei:teiCorpus[
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
  ][1]/string()
  let $title := $header/tei:fileDesc/tei:titleStmt/tei:title[1]/string()
  let $acronym := $header/tei:fileDesc/tei:titleStmt/tei:title[@type="acronym"][1]/string()
  let $repo := $header//tei:publicationStmt/tei:idno[@type="repo"][1]/string()
  let $projectDesc := $header/tei:encodingDesc/tei:projectDesc
  let $licence := $header//tei:publicationStmt/tei:availability/tei:licence
  let $description := if ($projectDesc) then (
    let $paras := for $p in $projectDesc/tei:p return local:markdown($p)
    return string-join($paras, "&#10;&#10;")
  ) else ()
  let $git-file := $config:corpora-root || "/" || $name || "/git.xml"
  let $sha := doc($git-file)/git/sha/text()

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
      if ($sha) then map:entry("commit", $sha) else (),
      if ($repo) then map:entry("repository", $repo) else (),
      if ($description) then map:entry("description", $description) else (),
      if ($licence)
        then map:entry("licence", normalize-space($licence[1])) else (),
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
  let $collection := concat($config:corpora-root, "/", $corpusname)

  for $tei in collection($collection)//tei:TEI
  let $id := dutil:get-dracor-id($tei)
  let $paths := dutil:filepaths(base-uri($tei))
  let $name := $paths?playname
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
  (: for antilabe (i.e. lines with a 'part' attribute) we count only the initial
  ones :)
  let $num-l := count($tei//tei:body//tei:sp//tei:l[not(@part) or @part = "I"])

  let $metrics := doc($paths?files?metrics)/metrics
  let $max-degree-ids := tokenize($metrics/network/maxDegreeIds)
  let $wikidata-id := dutil:get-play-wikidata-id($tei)
  let $sitelink-count := dutil:count-sitelinks($wikidata-id, $corpusname)

  let $networkmetrics := map:merge(
    for $s in $metrics/network/*[not(name() = ("maxDegreeIds", "nodes"))]
    let $v := $s/text()
    return map:entry(
      $s/name(),
      if(xs:string(number($v)) != "NaN") then number($v) else $v
    )
  )

  let $digitalSource := dutil:get-source($tei)?url

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
    "numOfActs": count($tei//tei:body//tei:div[@type="act"]),
    "numOfScenes": count($tei//tei:body//tei:div[@type="scene"]),
    "numOfSpeakers": $num-speakers,
    "numOfSpeakersMale": $num-male,
    "numOfSpeakersFemale": $num-female,
    "numOfSpeakersUnknown": $num-unknown,
    "numOfPersonGroups": $num-groups,
    "numOfP": $num-p,
    "numOfL": $num-l,
    "wikipediaLinkCount": $sitelink-count,
    "wordCountText": xs:integer($metrics/text/string()),
    "wordCountSp": xs:integer($metrics/sp/string()),
    "wordCountStage": xs:integer($metrics/stage/string()),
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
  order by $name
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
  let $source := $tei//tei:sourceDesc/tei:bibl[@type="digitalSource"][1]
  return if (count($source)) then map:merge((
    if ($source/tei:ref[@target]) then
      map {'name': $source/tei:ref[@target][1]/normalize-space()}
    (: deprecated :)
    else if ($source/tei:name) then
      map {'name': $source/tei:name[1]/normalize-space()}
    else (),
    if ($source/tei:ref[@target]) then
      map {'url': $source/tei:ref[@target][1]/@target/string()}
    (: deprecated :)
    else if ($source/tei:idno[@type="URL"]) then
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
  let $collection := $config:corpora-root || '/' || $corpus
  for $uri in collection($collection)
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
    let $paths := dutil:filepaths($corpusname, $playname)
    let $sha := doc($paths?files?git)/git/sha/text()
    let $tei := $doc//tei:TEI
    let $id := dutil:get-dracor-id($tei)
    let $uri := $paths?uri
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
          let $gender := $node/@gender/string()
          let $role := $node/@role/string()
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
            if ($gender) then map:entry("gender", $gender) else (),
            if ($role) then map:entry("role", $role) else (),
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
      if($sha) then map:entry("commit", $sha) else (),
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
      let $gender := $node/@gender/string()
      let $role := $node/@role/string()
      let $isGroup := if ($node/name() eq 'personGrp')
        then true() else false()
      let $num-of-speech := $tei//tei:sp[@who='#'||$id]
      let $metrics-node := $metrics//node[@id=$id]
      let $eigenvector := if ($metrics-node/eigenvector[text()]) then
        number($metrics-node/eigenvector) else 0
      let $wikidata-id := dutil:get-wikidata-id-from-ana($node)
      return map:merge((
        map {
          "id": $id,
          "name": $name,
          "isGroup": $isGroup,
          "sex": if($sex) then $sex else (),
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
        if ($gender) then map:entry("gender", $gender) else (),
        if ($role) then map:entry("role", $role) else (),
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
  let $listRel := $doc//tei:particDesc/tei:listPerson/tei:listRelation
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
  let $plays := collection($config:corpora-root)
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

(:~
 : Translate DraCor ID to URL
 :
 : @param $id DraCor ID
 : @param $accept MIME type
 :)
declare function dutil:id-to-url (
  $id as xs:string,
  $accept as xs:string*
) {
  let $tei := collection($config:corpora-root)/tei:TEI[@xml:id = $id][1]

  return if ($tei) then
    let $paths := dutil:filepaths(base-uri($tei))
    let $corpus := $paths?corpusname
    let $play := $paths?playname
    let $url := $config:api-base || "/corpora/" || $corpus || "/plays/" || $play

    return if ($accept = "application/json") then
      $url
    else if ($accept = "application/rdf+xml") then
      $url || "/rdf"
    else
      let $p := tokenize($config:api-base, '/')
      return $p[1] || '//' || $p[3] || '/' || $corpus || "/" || $play
  else ()
};

(:~
 : Create new corpus collection
 :
 : @param $corpus Map with corpus description
 :)
declare function dutil:create-corpus($corpus as map()) {
  let $xml :=
    <teiCorpus xmlns="http://www.tei-c.org/ns/1.0">
      <teiHeader>
        <fileDesc>
          <titleStmt>
            <title>{$corpus?title}</title>
          </titleStmt>
          <publicationStmt>
            <idno type="URI" xml:base="https://dracor.org/">{$corpus?name}</idno>
            {
              if ($corpus?repository)
              then <idno type="repo">{$corpus?repository}</idno>
              else ()
            }
          </publicationStmt>
        </fileDesc>
        {if ($corpus?description) then (
          <encodingDesc>
            <projectDesc>
              {
                for $p in tokenize($corpus?description, "&#10;&#10;")
                return <p>{$p}</p>
              }
            </projectDesc>
          </encodingDesc>
        ) else ()}
      </teiHeader>
    </teiCorpus>

  return dutil:create-corpus($corpus?name, $xml)
};

(:~
 : Create new corpus collection
 :
 : @param $name Corpus name
 : @param $xml Corpus description
 :)
declare function dutil:create-corpus(
  $name as xs:string,
  $xml as element(tei:teiCorpus)
) {
  util:log-system-out("creating corpus"),
  util:log-system-out($xml),
  xmldb:store(
    xmldb:create-collection($config:corpora-root, $name),
    "corpus.xml",
    $xml
  )
};

(:~
 : Determine Git SHA for corpus recorded in git.xml files
 :
 : @param $name Corpus name
 : @return string* Git SHA1 hash
 :)
declare function dutil:get-corpus-sha($name as xs:string) as xs:string* {
  let $col := collection($config:corpora-root || "/" || $name)
  let $num-plays := count($col/tei:TEI)
  let $num-sha := count($col/git/sha)
  let $shas := distinct-values($col/git/sha)

  return if($num-plays = $num-sha and count($shas) = 1) then $shas[1] else ()
};

declare function local:record-sha(
  $collection as xs:string,
  $sha as xs:string
) as xs:string* {
  try {
    xmldb:store( $collection, "git.xml", <git><sha>{$sha}</sha></git>)
  } catch * {
    util:log-system-out($err:description)
  }
};

(:~
 : Write commit SHA to git.xml file for play
 :
 : @param $corpusname Corpus name
 : @param $play Play name
 : @return string* Path to git.xml file
 :)
declare function dutil:record-sha(
  $corpusname as xs:string,
  $playname as xs:string,
  $sha as xs:string
) as xs:string* {
  let $paths := dutil:filepaths($corpusname, $playname)
  return local:record-sha($paths?collections?play, $sha)
};

(:~
 : Write commit SHA to git.xml file for corpus
 :
 : @param $corpusname Corpus name
 : @return string* Path to git.xml file
 :)
declare function dutil:record-sha(
  $corpusname as xs:string,
  $sha as xs:string
) as xs:string* {
  let $collection := $config:corpora-root || "/" || $corpusname
  return local:record-sha($collection, $sha)
};

declare function local:remove-sha($collection as xs:string) {
  if (doc-available($collection || "/git.xml")) then (
    util:log-system-out("Removing git.xml for " || $collection),
    xmldb:remove($collection, "git.xml")
  ) else ()
};

(:~
 : Remove corpus git.xml file
 :
 : @param $corpusname Corpus name
 : @return string* Path to git.xml file
 :)
declare function dutil:remove-corpus-sha(
  $corpusname as xs:string
) as xs:string* {
  let $collection := $config:corpora-root || "/" || $corpusname
  return local:remove-sha($collection)
};

(:~
 : Remove play git.xml file
 :
 : @param $corpusname Corpus name
 : @param $playname Play name
 :)
declare function dutil:remove-sha(
  $corpusname as xs:string,
  $playname as xs:string
) {
  let $collection :=
    $config:corpora-root || "/" || $corpusname || "/" || $playname
  return local:remove-sha($collection)
};

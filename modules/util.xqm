xquery version "3.1";

(:~
 : Module proving utility functions for dracor.
 :)
module namespace dutil = "http://dracor.org/ns/exist/util";

import module namespace functx="http://www.functx.com";
import module namespace config = "http://dracor.org/ns/exist/config"
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
declare function dutil:get-dracor-id($tei as element()) as xs:string* {
  $tei//tei:publicationStmt/tei:idno[@type="dracor"]/text()
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
  $tei//tei:body//(tei:div[tei:sp or (@type="scene" and not(.//tei:sp))]|tei:div1)
};

(:~
 : Determine the most fitting year from `written`, `premiere` and `print` of
 : the play passed in $tei.
 :
 : @param $tei The TEI root element of a play
 :)
declare function dutil:get-normalized-year ($tei as element()*) as item()* {
  let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
  let $written := $dates[@type="written"]/@when/string()
  let $premiere := $dates[@type="premiere"]/@when/string()
  let $print := $dates[@type="print"]/@when/string()

  let $published := if ($print and $premiere)
    then min(($print, $premiere))
    else if ($premiere) then $premiere
    else $print

  let $year := if ($written and $published)
    then
      if (xs:integer($published) - xs:integer($written) > 10)
      then $written
      else $published
    else if ($written) then $written
    else $published

  return $year
};

(:~
 : Count number of site links for play identified by $wikidata-id.
 :
 : @param $wikidata-id
 :)
declare function dutil:count-sitelinks(
  $wikidata-id as xs:string,
  $corpusname as xs:string
) {
  let $col := concat($config:sitelinks-root, "/", $corpusname)
  return count(collection($col)/sitelinks[@id=$wikidata-id]/uri)
};

(:~
 : Calculate meta data for corpus.
 :
 : @deprecated Use dutil:get-corpus-meta-data() instead.
 : @param $corpusname
 :)
declare function dutil:corpus-meta-data($corpusname as xs:string) as item()* {
  let $metrics-collection := concat($config:metrics-root, "/", $corpusname)
  let $metrics := for $s in collection($metrics-collection)//metrics
    let $uri := base-uri($s)
    let $fname := tokenize($uri, "/")[last()]
    let $name := tokenize($fname, "\.")[1]
    return <metrics name="{$name}">{$s/*}</metrics>

  let $collection := concat($config:data-root, "/", $corpusname)

  for $tei in collection($collection)//tei:TEI
  let $filename := tokenize(base-uri($tei), "/")[last()]
  let $name := tokenize($filename, "\.")[1]
  let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
  let $genre := $tei//tei:textClass/tei:keywords/tei:term[@type="genreTitle"]
    /@subtype/string()
  let $num-speakers := count(dutil:distinct-speakers($tei))
  let $stat := $metrics[@name=$name]
  let $max-degree-ids := tokenize($stat/network/maxDegreeIds)
  let $wikidata-id := $tei//tei:idno[@type="wikidata"]/text()
  let $sitelink-count := dutil:count-sitelinks($wikidata-id, $corpusname)
  order by $filename
  return
    <play>
      <name>{$name}</name>
      <genre>{$genre}</genre>
      <year>{dutil:get-normalized-year($tei)}</year>
      <numOfSegments>{count(dutil:get-segments($tei))}</numOfSegments>
      <numOfActs>{count($tei//tei:div[@type="act"])}</numOfActs>
      <numOfSpeakers>{$num-speakers}</numOfSpeakers>
      <yearWritten>{$dates[@type="written"]/@when/string()}</yearWritten>
      <yearPremiered>{$dates[@type="premiere"]/@when/string()}</yearPremiered>
      <yearPrinted>{$dates[@type="print"]/@when/string()}</yearPrinted>
      {$stat/network/*[not(name() = "maxDegreeIds")]}
      <maxDegreeIds>
        {
          if(count($max-degree-ids) < 4) then
            string-join($max-degree-ids, "|")
          else
            '"several characters"'
        }
      </maxDegreeIds>
      <wikipediaLinkCount>{$sitelink-count}</wikipediaLinkCount>
    </play>
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
  let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
  let $genre := $tei//tei:textClass/tei:keywords/tei:term[@type="genreTitle"]
    /@subtype/string()
  let $num-speakers := count(dutil:distinct-speakers($tei))
  let $stat := $metrics[@name=$name]
  let $max-degree-ids := tokenize($stat/network/maxDegreeIds)
  let $wikidata-id := $tei//tei:idno[@type="wikidata"]/text()
  let $sitelink-count := dutil:count-sitelinks($wikidata-id, $corpusname)

  let $networkmetrics := map:merge(
    for $s in $stat/network/*[not(name() = ("maxDegreeIds", "nodes"))]
    let $v := $s/text()
    return map:entry($s/name(), if(number($v)) then number($v) else $v)
  )
  let $meta := map {
    "id": $id,
    "name": $name,
    "playName": $name,
    "genre": $genre,
    "numOfSegments": count(dutil:get-segments($tei)),
    "numOfActs": count($tei//tei:div[@type="act"]),
    "numOfSpeakers": $num-speakers,
    "yearNormalized": xs:integer(dutil:get-normalized-year($tei)),
    "yearWritten": xs:integer($dates[@type="written"]/@when/string()),
    "yearPremiered": xs:integer($dates[@type="premiere"]/@when/string()),
    "yearPrinted": xs:integer($dates[@type="print"]/@when/string()),
    "maxDegreeIds": if(count($max-degree-ids) < 4) then
      string-join($max-degree-ids, "|")
    else
      "several characters",
    "wikipediaLinkCount": $sitelink-count
  }
  order by $filename
  return map:merge(($meta, $networkmetrics))
};

(:~
 : Retrieve author data from TEI.
 :
 : @param $tei
 :)
declare function dutil:get-authors($tei as node()) as map()* {
  for $author in $tei//tei:fileDesc/tei:titleStmt/tei:author
  let $name := if($author/tei:name[@type = "full"]) then
    $author/tei:name[@type = "full"]/string()
  else if ($author/tei:persName/tei:surname) then
    $author/tei:persName/tei:surname
    || ', '
    || $author/tei:persName/tei:forename
  else
    $author/string()
  return map {
    "name": $name,
    "key": $author/@key/string()
  }
};

(:~
 : Calculate meta data for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:play-info-map(
  $corpusname as xs:string,
  $playname as xs:string
) as map()? {
  let $doc := dutil:get-doc($corpusname, $playname)
  return if (not($doc)) then
    ()
  else
    let $tei := $doc//tei:TEI
    let $id := dutil:get-dracor-id($tei)
    let $subtitle :=
      $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
    let $source := $tei//tei:sourceDesc/tei:bibl[@type="digitalSource"]
    let $cast := dutil:distinct-speakers($doc//tei:body)
    let $lastone := $cast[last()]

    let $segments := array {
      for $segment at $pos in dutil:get-segments($tei)
      let $heads :=
        $segment/(ancestor::tei:div/tei:head,tei:head) ! normalize-space(.)
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
    let $genre := $tei//tei:textClass/tei:keywords/tei:term[@type="genreTitle"]
      /@subtype/string()
    let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date

    let $all-in-segment := $segments?*[?speakers=$lastone][1]?number
    let $all-in-index := $all-in-segment div count($segments?*)

    return map:merge((
      map {
        "id": $id,
        "name": $playname,
        "corpus": $corpusname,
        "title": $tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space(),
        "author": map {
          "name": $authors[1]?name,
          "warning": "The single author property is deprecated. " ||
          "Use the array of 'authors' instead!"
        },
        "authors": array {
          for $author in $authors
          return map {
            "name": $author?name,
            "key": $author?key
          }
        },
        "genre": $genre,
        "allInSegment": $all-in-segment,
        "allInIndex": $all-in-index,
        "cast": array {
          for $id in $cast
          let $node := $doc//tei:particDesc//(
            tei:person[@xml:id=$id] | tei:personGrp[@xml:id=$id]
          )
          let $name := $node/(tei:persName | tei:name)[1]/text()
          let $sex := $node/@sex/string()
          let $isGroup := if ($node/name() eq 'personGrp')
            then true() else false()
          return map {
            "id": $id,
            "name": $name,
            "isGroup": $isGroup,
            "sex": if($sex) then $sex else ()
          }
        },
        "segments": $segments,
        "yearWritten": xs:integer($dates[@type="written"]/@when/string()),
        "yearPremiered": xs:integer($dates[@type="premiere"]/@when/string()),
        "yearPrinted": xs:integer($dates[@type="print"]/@when/string()),
        "yearNormalized": xs:integer(dutil:get-normalized-year($tei))
      },
      if($subtitle) then
        map:entry("subtitle", $subtitle)
      else (),
      if($source) then
        map:entry("source", map {
          "name": $source/tei:name/string(),
          "url": $source/tei:idno[@type="URL"]/string()
        })
      else ()
    ))
};

(:~
 : Calculate meta data for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:play-info(
  $corpusname as xs:string,
  $playname as xs:string
) as item()* {
  let $doc := dutil:get-doc($corpusname, $playname)
  return
    if (not($doc)) then
      ()
    else
      let $tei := $doc//tei:TEI
      let $id := dutil:get-dracor-id($tei)
      let $subtitle :=
        $tei//tei:titleStmt/tei:title[@type='sub'][1]/normalize-space()
      let $cast := dutil:distinct-speakers($doc//tei:body)
      let $lastone := $cast[last()]
      let $segments :=
        <root>
        {
          for $segment in dutil:get-segments($tei)
          let $heads := $segment/(ancestor::tei:div/tei:head,tei:head) ! normalize-space(.)
          return
          <segments json:array="true">
            <type>{$segment/@type/string()}</type>
            {
              if (string-join($heads)) then
                <title>{string-join($heads, ' | ')}</title>
              else ()
            }
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
      let $authors := dutil:get-authors($tei)

      return
      <info>
        <id>{$id}</id>
        <name>{$playname}</name>
        <corpus>{$corpusname}</corpus>
        <title>
          {$tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space()}
        </title>
        {if ($subtitle) then <subtitle>{$subtitle}</subtitle> else ''}
        <author key="{$authors[1]?key}">
          <name>{$authors[1]?name}</name>
        </author>
        <_deprecationWarning>{normalize-space(
          "The single author property is deprecated. Use the array of 'authors'
          instead!")}
        </_deprecationWarning>
        {
          for $author in $authors
          return
            <authors key="{$author?key}" json:array="true">
              <name>{$author?name}</name>
            </authors>
        }
        <allInSegment>{$all-in-segment}</allInSegment>
        <allInIndex>{$all-in-index}</allInIndex>
        {
          for $id in $cast

          let $node := $doc//tei:particDesc//(
            tei:person[@xml:id=$id] | tei:personGrp[@xml:id=$id]
          )
          let $name := $node/(tei:persName | tei:name)[1]/text()
          let $sex := $node/@sex/string()
          let $isGroup := if ($node/name() eq 'personGrp')
            then true() else false()
          return
          <cast json:array="true">
            <id>{$id}</id>
            {if($name) then <name>{$name}</name> else ()}
            {if($isGroup) then <isGroup>true</isGroup> else ()}
            {if($sex) then <sex>{$sex}</sex> else ()}
          </cast>
        }
        {$segments//segments}
      </info>
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
    let $wikidata-id := $tei//tei:idno[@type="wikidata"]/text()
    let $sitelink-count := dutil:count-sitelinks($wikidata-id, $corpusname)

    let $nodes := array {
      for $n in $metrics/network/nodes/node
      return map:merge((
        map:entry("id", $n/@id/string()),
        for $s in $n/*
        let $v := $s/text()
        return map:entry($s/name(), if(number($v)) then number($v) else $v)
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
      return map:entry($e/name(), if(number($v)) then number($v) else $v)
    )
    
    return map:merge(($meta, $networkmetrics))
};

(:~
 : Compile cast info for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:cast-info (
  $corpusname as xs:string,
  $playname as xs:string
) as item()? {
  let $doc := dutil:get-doc($corpusname, $playname)
  return if (not($doc)) then
    ()
  else
    let $tei := $doc//tei:TEI
    let $cast := dutil:distinct-speakers($doc//tei:body)

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
      for $id in $cast
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
      return map {
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

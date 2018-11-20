xquery version "3.1";

(:~
 : Module proving utility functions for dracor.
 :)
module namespace dutil = "http://dracor.org/ns/exist/util";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare namespace json = "http://www.w3.org/2013/XSL/json";


(:~
 : Return document for a play.
 :
 : @param $corpusname
 : @param $playname
 :)
declare function dutil:get-doc(
  $corpusname as xs:string,
  $playname as xs:string
) as node() {
  let $doc := doc(
    $config:data-root || "/" || $corpusname || "/" || $playname || ".xml"
  )
  return $doc
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
 : Retrieve `div` elements considered a segment. These are usually `div`s
 : containing `sp` elements. However, also included are 'empty' scenes with no
 : speakers, e.g. those consisting only of stage directions.
 :
 : @param $tei The TEI root element of a play
 :)
declare function dutil:get-segments ($tei as element()*) as element()* {
  $tei//tei:body//tei:div[tei:sp or (@type="scene" and not(.//tei:sp))]
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
 : Calculate meta data for corpus.
 :
 : @param $corpusname
 :)
declare function dutil:corpus-meta-data($corpusname as xs:string) as item()* {
  let $stats-collection := concat($config:stats-root, "/", $corpusname)
  let $stats := for $s in collection($stats-collection)//stats
    let $uri := base-uri($s)
    let $fname := tokenize($uri, "/")[last()]
    let $name := tokenize($fname, "\.")[1]
    return <stats name="{$name}">{$s/*}</stats>

  let $collection := concat($config:data-root, "/", $corpusname)

  for $tei in collection($collection)//tei:TEI
  let $filename := tokenize(base-uri($tei), "/")[last()]
  let $name := tokenize($filename, "\.")[1]
  let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
  let $genre := $tei//tei:textClass/tei:keywords/tei:term[@type="genreTitle"]
    /@subtype/string()
  let $num-speakers := count(dutil:distinct-speakers($tei))
  let $stat := $stats[@name=$name]
  let $max-degree-ids := tokenize($stat/network/maxDegreeIds)
  let $wikidata-id := $tei//tei:idno[@type="wikidata"]/text()
  let $sitelinks-collection := concat($config:sitelinks-root, "/", $corpusname)
  let $sitelink-count := count(
    collection($sitelinks-collection)/sitelinks[@id=$wikidata-id]/uri
  )
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

      return
      <info>
        <id>{$playname}</id>
        <corpus>{$corpusname}</corpus>
        <title>
          {$tei//tei:fileDesc/tei:titleStmt/tei:title[1]/normalize-space()}
        </title>
        {if ($subtitle) then <subtitle>{$subtitle}</subtitle> else ''}
        <author key="{$tei//tei:fileDesc/tei:titleStmt/tei:author/@key}">
          <name>{$tei//tei:fileDesc/tei:titleStmt/tei:author/string()}</name>
        </author>
        <_deprecationWarning>{normalize-space(
          "The single author property is deprecated. Use the array of 'authors'
          instead!")}
        </_deprecationWarning>
        {
          for $author in $tei//tei:fileDesc/tei:titleStmt/tei:author
          return
            <authors key="{$author/@key}" json:array="true">
              <name>{$author/string()}</name>
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

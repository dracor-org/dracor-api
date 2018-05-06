xquery version "3.1";

(:~
 : Module proving utility functions for dracor.
 :)
module namespace dutil = "http://dracor.org/ns/exist/util";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Retrieve the speaker children of a given element and return the distinct IDs
 : referenced in @who attributes of those elements.
 :)
declare function dutil:distinct-speakers ($parent as element()*) as item()* {
    let $whos :=
      for $w in $parent//tei:sp/@who
      return tokenize(normalize-space($w), '\s+')
    for $ref in distinct-values($whos) return substring($ref, 2)
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
  let $collection := concat($config:data-root, "/", $corpusname)
  for $tei in collection($collection)//tei:TEI
  let $filename := tokenize(base-uri($tei), "/")[last()]
  let $name := tokenize($filename, "\.")[1]
  let $dates := $tei//tei:bibl[@type="originalSource"]/tei:date
  let $genre := $tei//tei:textClass/tei:keywords/tei:term[@type="genreTitle"]
    /@subtype/string()
  let $num-speakers := count(dutil:distinct-speakers($tei))
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
    </play>
};

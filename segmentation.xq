xquery version "3.1";

import module namespace xdb = "http://exist-db.org/xquery/xmldb";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare variable $corpus := request:get-parameter("corpus", "ger");
declare variable $filename := request:get-parameter(
  "drama",
  "goethe-faust-der-tragoedie-zweiter-teil"
);

declare function local:distinct-speakers ($parent as element()) as item()* {
    let $whos := for $w in $parent//tei:sp/@who return tokenize($w, '\s+')
    for $ref in distinct-values($whos) return substring($ref, 2)
};

let $file := concat("/db/data/dracor/", $corpus, "/", $filename, ".xml")
let $doc := xdb:document($file)
let $cast := local:distinct-speakers($doc//tei:body)
let $segments := $doc//tei:body//tei:div[tei:sp]

return
<result file="{$file}">
  <cast>
    {
      for $id in $cast
      let $name := $doc//tei:particDesc//(tei:person[@xml:id=$id]/tei:persName[1]|tei:persName[@xml:id=$id])/text()
      return <member id="{$id}">{$name}</member>
    }
  </cast>
  <segments count="{count($segments)}">
    {
      for $seg at $pos in $segments
      let $heads := $seg/(ancestor::tei:div/tei:head|tei:head)
      return
      <sgm n="{$pos}" type="{$seg/@type}" title="{string-join($heads, ' | ')}">
        {
          for $id in local:distinct-speakers($seg)
          return <spkr>{$id}</spkr>
        }
      </sgm>
    }
  </segments>
</result>

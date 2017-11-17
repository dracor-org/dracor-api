xquery version "3.1";

import module namespace xdb = "http://exist-db.org/xquery/xmldb";
import module namespace dutil = "http://dracor.org/ns/exist/util"
  at "modules/util.xqm";
import module namespace config="http://dracor.org/ns/exist/config"
  at "modules/config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";
declare variable $corpus := request:get-parameter("corpus", "ger");
declare variable $filename := request:get-parameter(
  "drama",
  "goethe-faust-der-tragoedie-zweiter-teil"
);

let $file := concat($config:data-root, "/", $corpus, "/", $filename, ".xml")
let $doc := xdb:document($file)
let $status := if(not($doc)) then response:set-status-code(404) else ()
let $cast := dutil:distinct-speakers($doc//tei:body)
let $segments := $doc//tei:body//tei:div[tei:sp]

return
<result file="{$file}">
  {
    if(not($doc)) then
      <error>no such file</error>
    else (
      <cast>
        {
          for $id in $cast
          let $name := $doc//tei:particDesc//(tei:person[@xml:id=$id]/tei:persName[1]|tei:persName[@xml:id=$id])/text()
          return <member id="{$id}">{$name}</member>
        }
      </cast>,
      <segments count="{count($segments)}">
        {
          for $seg at $pos in $segments
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
    )
  }
</result>

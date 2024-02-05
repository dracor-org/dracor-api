xquery version "3.1";

(:~
 : Module providing function to load files from zip archives.
 :)
module namespace load = "http://dracor.org/ns/exist/v1/load";

import module namespace config = "http://dracor.org/ns/exist/v1/config"
  at "config.xqm";
import module namespace metrics = "http://dracor.org/ns/exist/v1/metrics"
  at "metrics.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util"
  at "util.xqm";
import module namespace drdf = "http://dracor.org/ns/exist/v1/rdf" at "rdf.xqm";

declare namespace compression = "http://exist-db.org/xquery/compression";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare function local:entry-data(
  $path as xs:anyURI,
  $type as xs:string,
  $data as item()?,
  $param as item()*
) as item()? {
  if($data) then
    let $collection := $param[1]
    let $filename := tokenize($path, "/")[last()]
    let $name := replace($filename, "\.xml$", "")
    let $log := util:log-system-out("LOADING " || $path)
    let $res := if ($name = "corpus") then
      xmldb:store($collection, "corpus.xml", $data)
    else
      let $play-collection := xmldb:create-collection($collection, $name)
      return xmldb:store($play-collection, "tei.xml", $data)
    return $res
  else
    ()
};

declare function local:entry-filter(
  $path as xs:anyURI, $type as xs:string, $param as item()*
) as xs:boolean {
  (: filter paths using only corpus.xml or files in the "tei" subdirectory :)
  if ($type eq "resource" and (
    contains($path, "/tei/") or contains($path, "corpus.xml")
  ))
  then
    true()
  else
    false()
};

(:~
 : Load corpus from ZIP archive
 :
 : @param $corpus The <corpus> element providing corpus name and archive URL
 : @return List of created collections and files
:)
declare function load:load-corpus($corpus as element(tei:teiCorpus))
as xs:string* {
  let $info := dutil:get-corpus-info($corpus)
  let $name := $info?name

  let $corpus-collection := $config:corpora-root || "/" || $name

  let $archive :=
    if ($info?archive) then
      $info?archive
    else if (starts-with($info?repository, "https://github.com")) then
      $info?repository || "/archive/main.zip"
    else ()

  return
    if (not($archive)) then (
      util:log-system-out("cannot determine archive URL")
    )
    else
      let $log := util:log-system-out("loading " || $archive)
      let $request := <hc:request method="get" href="{ $archive }" />
      let $response := hc:send-request($request)
      return
        if ($response[1]/@status = "200") then
          let $body := $response[2]
          let $zip := xs:base64Binary($body)
          return (
            util:log-system-out("removing " || $corpus-collection),
            xmldb:remove($corpus-collection),

            (: Re-create corpus :)
            util:log-system-out("recreating " || $name),
            dutil:create-corpus($info),

            (: clear fuseki graph :)
            drdf:fuseki-clear-graph($name),

            (: load files from ZIP archive :)
            compression:unzip(
              $zip,
              util:function(xs:QName("local:entry-filter"), 3),
              (),
              util:function(xs:QName("local:entry-data"), 4),
              ($corpus-collection)
            )
          )
        else (
          util:log("warn", ("cannot load archive ", $archive)),
          util:log("info", $response)
        )
};

(:~
 : Update generated files for all plays in the database
:)
declare function load:update() as xs:string* {
  metrics:update(), drdf:update()
};

xquery version "3.0";

import module namespace xdb = "http://exist-db.org/xquery/xmldb";
declare namespace compression = "http://exist-db.org/xquery/compression";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare function local:mkcol-recursive($collection, $components) {
  if (exists($components)) then
    let $newColl := concat($collection, "/", $components[1])
    return (
      xdb:create-collection($collection, $components[1]),
      local:mkcol-recursive($newColl, subsequence($components, 2))
    )
  else
    ()
  };

declare function local:mkcol($collection, $path) {
  local:mkcol-recursive($collection, tokenize($path, "/"))
};

declare function local:entry-data(
  $path as xs:anyURI, $type as xs:string, $data as item()?, $param as item()*
) as item()? {
  if($data) then
    let $collection := $param[1]
    let $name := tokenize($path, '/')[last()]
    let $res := xdb:store($collection, $name, $data)
    return $res
  else
    ()
};

declare function local:entry-filter(
  $path as xs:anyURI, $type as xs:string, $param as item()*
) as xs:boolean {
  if ($type eq "resource" and contains($path, "/tei/")) then
    true()
  else
    false()
};

let $target := "/db"
let $path := "data/dracor"
let $collection := concat($target, "/", $path)
let $url := "https://github.com/lehkost/RusDraCor/archive/master.zip"
let $gitRepo := httpclient:get($url, false(), ())
let $zip := xs:base64Binary(
  $gitRepo//httpclient:body[@mimetype="application/zip"][@type="binary"]
    [@encoding="Base64Encoded"]/string(.)
)
return (
  local:mkcol($target, $path),
  compression:unzip(
    $zip,
    util:function(xs:QName("local:entry-filter"), 3),
    (),
    util:function(xs:QName("local:entry-data"), 4),
    ($collection)
  )
)

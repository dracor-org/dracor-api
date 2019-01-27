xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "../modules/config.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare variable $local:delivery external;

declare variable $local:corpora := collection($config:data-root)/corpus;

declare function local:update (
  $source as xs:string,
  $target as xs:string
) as xs:boolean {
  let $filename := tokenize($target, '/')[last()]
  let $collection := substring(
    $target, 1, string-length($target) - string-length($filename) - 1
  )
  let $l := util:log("info", "Fetching " || $source)
  let $response := httpclient:get($source, false(), ())
  let $status := $response/@statusCode/string()
  let $body := $response//httpclient:body
  return if ($status = "200") then
    let $data := if ($body[@type="xml"]/tei:TEI) then $body/tei:TEI else (
      util:log("warn", "Not a TEI document: " || $source)
    )
    let $l := util:log-system-out($data)
    return if ($data) then
      if (
        util:log("info", "Updating " || $target),
        xmldb:store(
          $collection,
          xmldb:encode-uri($filename),
          $data
        )
      ) then true() else false()
    else false()
  else (
    util:log("warn", "Fetching " || $source || " failed. Status: " || $status),
    false()
  )
};

declare function local:remove ($file as xs:string) as xs:boolean {
  let $filename := tokenize($file, '/')[last()]
  let $collection := substring(
    $file, 1, string-length($file) - string-length($filename) - 1
  )
  return
    try {
      (xmldb:remove($collection, $filename), true())
    } catch * {
      util:log("warn", $err:description), false()
    }
};

declare function local:handle-file ($file as element(file)) as item() {
  let $repo := $file/@repo/string()
  let $corpus := collection($config:data-root)/corpus[repository = $repo]
  let $corpusname := $corpus/name/normalize-space()
  let $path := $file/@path/string()
  let $source := $file/@source/string()
  let $target := $config:data-root || '/' || $corpusname
    || replace($path, '^' || $config:corpus-repo-prefix, '')
  let $action := $file/@action
  return
    if(not(starts-with($path, $config:corpus-repo-prefix))) then
      map {"path": $path, "action": "skip"}
    else if ($action = 'remove') then
      map {
        "path": $path,
        "action": "remove",
        "uri": $target,
        "status": if (local:remove($target)) then "ok" else "failed"
      }
    else
      map {
        "path": $path,
        "action": "update",
        "uri": $target,
        "status": if (local:update($source, $target)) then "ok" else "failed"
      }
};

declare function local:process-delivery () {
  let $delivery := collection($config:webhook-root)
    /delivery[@id = $local:delivery and not(@processed)]
  return if($delivery/@repo/string() = $local:corpora/repository) then
    let $l := util:log("info", "Processing webhook delivery: " || $local:delivery)
    let $updates := for $file in $delivery//file
      let $result := local:handle-file($file)
      let $u := if($result?status = "ok") then
        update insert attribute updated {current-dateTime()} into $file
      else
        update insert attribute failed {current-dateTime()} into $file
      return $result
    return (
      update insert attribute processed {current-dateTime()} into $delivery,
      $delivery
    )
  else if ($delivery) then
    util:log-system-err(
      "Repo " || $delivery/@repo || " of delivery " || $local:delivery ||
        " not defined"
    )
  else
    util:log("info", "Delivery not found")
};

util:log-system-out("Processing webhook delivery: " || $local:delivery),
local:process-delivery()

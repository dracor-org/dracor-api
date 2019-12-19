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
  let $request := <hc:request method="get" href="{$source}" />
  let $response := hc:send-request($request)
  let $status := string($response[1]/@status)

  return if ($status = "200") then
    let $data := if (
      starts-with($response[1]/hc:body/@media-type, "application/json")
    ) then
      let $json := parse-json(
        util:base64-decode($response[2])
      )
      return util:base64-decode($json?content)
    else
      $response[2]

    (: FIXME: make sure $data is valid TEI :)

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

declare function local:get-repo-contents ($url-template) {
  let $url := replace($url-template, '\{\+path\}', $config:corpus-repo-prefix)
  let $request := <hc:request method="get" href="{ $url }" />
  let $response := hc:send-request($request)
  let $json := parse-json(util:base64-decode($response[2]))
  return
      $json
};

declare function local:process-delivery () {
  let $delivery := collection($config:webhook-root)
    /delivery[@id = $local:delivery and not(@processed)]
  let $repo := $delivery/@repo/string()
  let $corpus := $local:corpora[repository = $repo]
  let $corpusname := $corpus/name/normalize-space()

  return if($corpus) then
    let $l := util:log(
      "info", "Processing webhook delivery: " || $local:delivery
    )
    let $contents := local:get-repo-contents($delivery/@contents-url/string())
    let $files := $delivery//file[
      starts-with(@path, $config:corpus-repo-prefix)
    ]

    let $updates := for $file in $files
      let $path := $file/@path/string()
      let $target := $config:data-root || '/' || $corpusname
        || replace($path, '^' || $config:corpus-repo-prefix, '')
      let $action := $file/@action

      let $result := if ($action = "remove") then
        local:remove($target)
      else
        let $source := $contents?*[?type = "file" and ?path = $path]?git_url
        return local:update($source, $target)

      let $u := if($result) then
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

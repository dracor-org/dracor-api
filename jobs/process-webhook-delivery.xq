xquery version "3.1";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "../modules/config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util"
  at "../modules/util.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare variable $local:delivery external;

declare variable $local:gh-client-id :=
  environment-variable('DRACOR_GH_CLIENT_ID');

declare variable $local:gh-client-secret :=
  environment-variable('DRACOR_GH_CLIENT_SECRET');

declare function local:gh-request (
  $method as xs:string,
  $href as xs:string
) as item()+ {
  let $request :=
    <hc:request method="{$method}" href="{$href}">
      {
        if ($local:gh-client-id) then (
          attribute {"auth-method"} {"basic"},
          attribute {"send-authorization"} {"true"},
          attribute {"username"} {$local:gh-client-id},
          attribute {"password"} {$local:gh-client-secret}
        ) else ()
      }
    </hc:request>
  (: let $l := util:log("info", $request) :)
  return hc:send-request($request)
};

declare function local:update (
  $source as xs:string,
  $target as xs:string
) as xs:boolean {
  let $filename := tokenize($target, '/')[last()]
  let $collection := substring(
    $target, 1, string-length($target) - string-length($filename) - 1
  )
  let $l := util:log("info", "Fetching " || $source)
  let $response := local:gh-request("get", $source)
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

declare function local:make-url ($template, $path) {
  let $url := replace($template, '\{\+path\}', $path)
  return $url
};

declare function local:get-repo-contents ($url-template) {
  let $url := local:make-url($url-template, $config:corpus-repo-prefix)
  let $response := local:gh-request("get", $url)
  let $json := parse-json(util:base64-decode($response[2]))
  return $json
};

declare function local:process-delivery () {
  let $delivery := collection($config:webhook-root)
    /delivery[@id = $local:delivery and not(@processed)]
  let $repo := $delivery/@repo/string()
  let $corpus := collection($config:data-root)//tei:teiCorpus[
    tei:teiHeader//tei:publicationStmt/tei:idno[@type="repo" and . = $repo]
  ]

  let $info := dutil:get-corpus-info($corpus)
  let $corpusname := $info?name

  return if($corpus) then
    let $l := util:log(
      "info", "Processing webhook delivery: " || $local:delivery
    )
    let $contents-url := $delivery/@contents-url/string()
    let $contents := local:get-repo-contents($contents-url)
    let $files := $delivery//file[
      @path = "corpus.xml" or
      starts-with(@path, $config:corpus-repo-prefix)
    ]

    let $updates := for $file in $files
      let $path := $file/@path/string()
      let $source := if ($path = "corpus.xml")
        then local:make-url($contents-url, $path)
        else $contents?*[?type = "file" and ?path = $path]?git_url
      let $target := $config:data-root || '/' || $corpusname || '/'
        || replace($path, '^' || $config:corpus-repo-prefix || '/', '')
      let $action := $file/@action

      let $result := if ($action = "remove") then
        local:remove($target)
      else if ($source) then
        local:update($source, $target)
      else ()

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

xquery version "3.1";

module namespace webhook = "http://dracor.org/ns/exist/webhook";

import module namespace crypto="http://expath.org/ns/crypto";
import module namespace config = "http://dracor.org/ns/exist/config"
  at "config.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

declare variable $webhook:secret :=
  environment-variable('GITHUB_WEBHOOK_SECRET');
declare variable $webhook:check-agent := true();

declare function local:check-signature (
  $data as xs:string,
  $sig as xs:string
) as xs:boolean {
  if (not($config:webhook-secret)) then
    (util:log('warn', 'Missing Github webhook secret'), false())
  else
    let $hash := crypto:hmac($data, $config:webhook-secret, 'HMAC-SHA-1', 'hex')
    let $test := concat('sha1=', $hash)
    (: let $log := util:log('info', concat('Signature: ', $sig, ' Test: ', $test)) :)
    return if($test = $sig) then true() else false()
};

declare function local:get-corpus ($repo-url as xs:string) as element()? {
  collection($config:data-root)/corpus[repository = $repo-url]
};

declare function local:check-repo ($url as xs:string) as xs:boolean {
  if (local:get-corpus($url)) then true() else false()
};

declare function local:get-files ($payload as map(*)) as item()* {
  let $repo := $payload?repository?html_url
  let $source-base := 'https://raw.githubusercontent.com/'
    || $payload?repository?full_name || '/master/'
  (: first collect all modified files in the order of commits :)
  let $changes :=
    <changes>
    {
      for $commit in $payload?commits?*
      let $id := $commit?id
      return (
        for $path in $commit?added?*
        let $source :=  $source-base || $path
        return <file action="add" path="{$path}" repo="{$repo}"
                     source="{$source}" commit="{$id}"/>,
        for $path in $commit?removed?*
        return <file action="remove" path="{$path}" repo="{$repo}"
                     commit="{$id}"/>,
        for $path in $commit?modified?*
        let $source :=  $source-base || $path
        return <file action="modify" path="{$path}" repo="{$repo}"
                     source="{$source}" commit="{$id}"/>
      )
    }
    </changes>
  (: now normalize the list of files to handle :)
  let $files := for $file in $changes/*
    let $p := $file/@path
    return
      if ($file/following-sibling::*[@path = $p]) then () else $file

  return $files
};

declare function local:handle-delivery (
  $delivery-id as xs:string,
  $payload as map(*)
) as item()* {
  let $date := format-dateTime(
    current-dateTime(),
    "[Y0001][M01][D01][H01][m01][s01]"
  )
  let $id := replace($delivery-id, "[^-a-zA-Z\d]", "_")
  let $fname := concat($date, "-", $id, ".xml")
  let $l := util:log("info", "recording webhook delivery " || $delivery-id)
  let $files := local:get-files($payload)
  let $doc :=
    <delivery
      id="{$delivery-id}"
      pusher="{$payload?pusher?name}"
      repo="{$payload?repository?html_url}"
    >
      {$files}
    </delivery>
  let $col := xmldb:create-collection('/', $config:webhook-root)
  let $result := xmldb:store($col, $fname, $doc)
  return $result
};

declare
  %rest:POST("{$data}")
  %rest:path("/webhook/github")
  %rest:header-param("User-Agent", "{$agent}")
  %rest:header-param("X-GitHub-Event", "{$event}")
  %rest:header-param("X-GitHub-Delivery", "{$delivery}")
  %rest:header-param("X-Hub-Signature", "{$signature}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function webhook:github($data, $agent, $event, $delivery, $signature) {
  let $payload := util:base64-decode($data)
  let $json := if ($payload) then parse-json($payload) else parse-json('{}')
  (: let $l := util:log-system-out("SECRET " || $config:webhook-secret)
  let $l := util:log-system-out("PAYLOAD " || $payload)
  let $l := util:log-system-out("SIGNATURE " || $signature) :)
  return
    if (not($config:webhook-secret)) then
      (
        <rest:response><http:response status="501"/></rest:response>,
        map {"message": "Webhook secret not configured"}
      )
    else if (
      $webhook:check-agent and not(matches($agent, '^GitHub-Hookshot/'))
    ) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "Invalid user agent, expecting GitHub-Hookshot."}
      )
    else if ($event = 'ping') then
      map {"message": "Pong ;-)"}
    else if (not($event = 'push')) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "Invalid GitHub Event, expecting push."}
      )
    else if (not($signature)) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "Missing signature."}
      )
    else if (not($event = 'push')) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "Invalid GitHub Event, expecting push."}
      )
    else if (not(local:check-signature($payload, $signature))) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {
          "message": "Invalid signature " || $signature
        }
      )
    else if (not($delivery)) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "Missing delivery ID."}
      )
    else if (not($json?ref = 'refs/heads/master')) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {"message": "Not from master branch."}
      )
    else if (not(local:check-repo($json?repository?html_url))) then
      (
        <rest:response><http:response status="400"/></rest:response>,
        map {
          "message": "Repository '" || $json?repository?html_url
            || "' is not configured."
        }
      )
    else
      let $result := local:handle-delivery($delivery, $json)
      return if (not($result)) then
        (
          <rest:response><http:response status="500"/></rest:response>,
          map {"message": "An error occured."}
        )
        else map {
          "message": "Delivery accepted.",
          "result": $result,
          "scheduled": scheduler:schedule-xquery-periodic-job(
            "/db/apps/dracor/jobs/process-webhook-delivery.xq",
            1000,
            "webhook-update-" || $delivery,
            (
              <parameters>
                <param name="delivery" value="{$delivery}"/>
              </parameters>
            ), 5000, 0
          )
        }
};

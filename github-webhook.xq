xquery version "3.1";

(:~
 : XQuery endpoint handling GitHub webhook requests. The query responds to
 : push events only. 
 :
 : This script has been largely inspired by Winona Salesky's git-sync.xql
 : (https://gist.github.com/wsalesky/bf26507ff593f0c99a35), which has been
 : updated to use eXist's httpclient library and builtin parse-json().
 :
 : The EXPath Cryptographic Module Implementation supplies the HMAC-SHA1
 : algorithm for validating the GitHub signature against the shared secret.
 : Note: version 0.3.5 of the library is required.
 :
 : The secret is expected to be provided in the environmental variable
 : GITHUB_WEBHOOK_SECRET.
 :
 : The query needs to be run with administrative privileges to be able to
 : actually update the database from
 :
 : @author Carsten Milling
 :
 : @see http://expath.org/spec/crypto
 :)

import module namespace crypto="http://expath.org/ns/crypto";
import module namespace config="http://dracor.org/ns/exist/config"
  at "modules/config.xqm";

declare variable $secret := environment-variable('GITHUB_WEBHOOK_SECRET');

declare function local:check-signature (
  $data as xs:string,
  $sig as xs:string
) as xs:boolean {
  if (not($secret)) then
    let $log := util:log('warn', 'Missing Github webhook secret')
    return false()
  else
    let $hash := crypto:hmac($data, $secret, 'HMAC-SHA-1', 'hex')
    let $test := concat('sha1=', $hash)
    (: let $log := util:log('info', concat('Signature: ', $sig, ' Test: ', $test)) :)
    return if($test = $sig) then true() else false()
};

declare function local:get-corpus ($repo-url as xs:string) as element() {
  $config:corpora//corpus[repository = $repo-url]
};

declare function local:check-repo ($url as xs:string) as xs:boolean {
  if (local:get-corpus($url)) then true() else false()
};

(:~ 
 : Recursively creates new collections if necessary 
 : @param $uri url to resource being added to db
 :)
declare function local:create-collections ($uri as xs:string) {
  let $collection-uri := substring($uri,1)
  for $collections in tokenize($collection-uri, '/')
  let $current-path := concat(
    '/',
    substring-before($collection-uri, $collections),
    $collections
  )
  let $parent-collection := substring(
    $current-path, 1,
    string-length($current-path)
      - string-length(tokenize($current-path, '/')[last()])
  )
  return
    if (xmldb:collection-available($current-path)) then ()
    else xmldb:create-collection($parent-collection, $collections)
};

declare function local:remove ($file as xs:string) as node()* {
  let $filename := tokenize($file, '/')[last()]
  let $collection := substring(
    $file, 1, string-length($file) - string-length($filename) - 1
  )
  return
    try {
      <remove>{xmldb:remove($collection, $filename)}</remove>
    } catch * {
      util:log('warn', $err:description),
      <error>failed to remove resource</error>
    }
};

declare function local:update (
  $source as xs:string,
  $target as xs:string
) as node()* {
  let $filename := tokenize($target, '/')[last()]
  let $collection := substring(
    $target, 1, string-length($target) - string-length($filename) - 1
  )
  return
    try {
      let $log := util:log('info', concat('Updating resource ', $target))
      let $response := httpclient:get($source, false(), ())
      let $body := $response//httpclient:body
        [@mimetype="application/json; charset=utf-8"]
        [@encoding="Base64Encoded"]/string(.)
      let $json := parse-json(util:base64-decode($body))
      return (
        if (xmldb:collection-available($collection)) then ()
        else local:create-collections($collection),
        <update>
          {xmldb:store(
            $collection,
            xmldb:encode-uri($filename),
            xs:base64Binary($json?content)
          )}
        </update>
      )
    } catch * {
      util:log('warn', $err:description),
      <error>failed to update resource</error>
    }
};


declare function local:handle-file (
  $file as item(),
  $repo as map(*)
) as item() {
  let $corpus := local:get-corpus($repo?html_url)
  let $path := $file/@path
  let $prefix := if ($corpus/prefix) then $corpus/prefix/text() else ''

  let $repo-source := replace($repo?contents_url, '\{\+path\}', $path)
  let $db-resource := concat(
    $config:data-root,
    '/',
    normalize-space($corpus/name),
    '/',
    if ($prefix) then replace($path, concat('^', $prefix), '') else $path
  )
  let $action := $file/@action
  return
    if($prefix and not(starts-with($path, $prefix))) then
      <action type="skip" path="{$path}" />
    else if ($action = 'remove') then
      <action type="remove" resource="{$db-resource}">
        {local:remove($db-resource)}
      </action>
    else
      <action type="update" resource="{$db-resource}">
        {local:update($repo-source, $db-resource)}
      </action>
};


let $check-agent := true()
let $post-data := util:base64-decode(request:get-data())
let $payload := if ($post-data) then parse-json($post-data) else parse-json('{}')
let $signature := request:get-header('X-Hub-Signature')
return
  if (not(request:get-method() = 'POST')) then
    <response status="fail">
      <message>Method not allowed, expecting POST.</message>
    </response>
  else if(not($post-data)) then
    <response status="fail">
      <message>No post data recieved.</message>
    </response>
  else if (
    $check-agent and
    not(matches(request:get-header('User-Agent'), '^GitHub-Hookshot/'))
  ) then
    <response status="fail">
      <message>Invalid user agent, expecting GitHub-Hookshot.</message>
    </response>
  else if (request:get-header('X-GitHub-Event') = 'ping') then
    <response status="ok">
      <message>Pong ;-)</message>
    </response>
  else if (not(request:get-header('X-GitHub-Event') = 'push')) then
    <response status="fail">
      <message>Invalid GitHub Event, expecting push.</message>
    </response>
  else if (not($signature)) then
    <response status="fail">
      <message>Missing signature.</message>
    </response>
  else if (not(local:check-signature($post-data, $signature))) then
    <response status="fail">
      <message>
        Invalid signature {$signature}
      </message>
    </response>
  else if (not($payload?ref = 'refs/heads/master')) then
    <response status="fail">
      <message>Not from master branch.</message>
    </response>
  else if (not(local:check-repo($payload?repository?html_url))) then
    <response status="fail">
      <message>
        Repository '{$payload?repository?html_url}' is not configured.
      </message>
    </response>
  else
    (: first collect all modified files in the order of commits :)
    let $changes :=
      <changes>
      {
        for $commit in $payload?commits?*
        let $id := $commit?id
        return (
          for $path in $commit?added?*
          return <file commit="{$id}" action="add" path="{$path}"/>,
          for $path in $commit?removed?*
          return <file commit="{$id}" action="remove" path="{$path}"/>,
          for $path in $commit?modified?*
          return <file commit="{$id}" action="modify" path="{$path}"/>
        )
      }
      </changes>
    (: now normalize the list of files to handle :)
    let $files :=
      <files>
        {
          for $file in $changes/*
          let $p := $file/@path
          return
            if ($file/following-sibling::*[@path = $p]) then () else $file
        }
      </files>
    (: now handle each file and gather results :)
    let $results :=
      <results>
        {
          for $file in $files/*
          return local:handle-file($file, $payload?repository)
        }
      </results>

    return
    <response status="ok">
      {$changes}
      {$files}
      {$results}
    </response>

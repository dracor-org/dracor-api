xquery version "3.1";

(:~
 : DraCor ID resolver
 :
 : Resolves DraCor play IDs (`/id/{id}`) to the play page, the JSON metadata or
 : the RDF of a play, depending on the `Accept` header.
 :
 : This module takes over the resolver from api.xqm (api:id-to-url) and
 : dutil:id-to-url, unchanged in behaviour. It is the place where resolving
 : play versions (`/id/{id}@{commit}`) will be added.
 :)
module namespace resolver = "http://dracor.org/ns/exist/v1/resolver";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

(:~
 : Resolve DraCor ID of a play
 :
 : Depending on the `Accept` header this endpoint redirects to either the RDF
 : representation, the JSON metadata or the dracor.org page of the play
 : identified by $id.
 :
 : @param $id DraCor ID
 : @param $accept Accept header value
 : @result redirect
 :)
declare
  %rest:GET %rest:path("/v1/id/{$id}") %rest:header-param("Accept", "{$accept}")
function resolver:resolve($id, $accept) {
  let $url := resolver:id-to-url($id, $accept)
  return if (not($url)) then
    <rest:response><http:response status="404" /></rest:response>
  else
    <rest:response>
      <http:response status="303">
        <http:header name="location" value="{ $url }" />
      </http:response>
    </rest:response>
};

(:~
 : Translate DraCor ID to URL
 :
 : @param $id DraCor ID
 : @param $accept MIME type
 :)
declare function resolver:id-to-url($id as xs:string, $accept as xs:string*) {
  let $tei := dutil:get-play-by-id($id)

  return if ($tei) then
    let $paths := dutil:filepaths(base-uri($tei))
    let $corpus := $paths?corpusname
    let $play := $paths?playname
    let $url := $config:api-base || "/corpora/" || $corpus || "/plays/" || $play

    return if ($accept = "application/json") then
      $url
    else if ($accept = "application/rdf+xml") then
      $url || "/rdf"
    else
      $config:api-origin || "/" || $corpus || "/" || $play
  else (
  )
};

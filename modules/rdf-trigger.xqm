xquery version "3.1";

module namespace drdft = "http://dracor.org/ns/exist/trigger";

import module namespace console="http://exist-db.org/xquery/console";

declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";
declare namespace trigger = "http://exist-db.org/xquery/trigger";

 (:~
 : Send RDF data to Fuseki
 https://github.com/dracor-org/dracor-api/issues/77
 :)
declare function trigger:after-create-document($uri as xs:anyURI) {
  let $corpus := tokenize($uri, "/")[position() = last() - 1]
  let $url := "http://localhost:3030/dracor/data?graph=" || encode-for-uri("http://dracor.org/" || $corpus)
  let $rdf := doc($uri)
  let $request :=
    <hc:request method="put" href="{ $url }">
      <hc:body media-type="application/rdf+xml">{ $rdf }</hc:body>
    </hc:request>
  let $response :=
      hc:send-request($request)
  let $console := console:log( $response[1] )
  return
    true()
};

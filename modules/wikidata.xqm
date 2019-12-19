xquery version "3.1";

(:~
 : Module bridging dracor and wikidata.
 :)
module namespace wd = "http://dracor.org/ns/exist/wikidata";

declare namespace sparqlres = "http://www.w3.org/2005/sparql-results#";
declare variable $wd:sparql-endpoint := 'https://query.wikidata.org/sparql';

(:~
 : Query links to wikipedia articles for given wikidata ID
 :
 : @param $id Wikidata ID (of a play)
:)
declare function wd:get-sitelinks($id as xs:string) as xs:string* {
    let $sparql := 'SELECT ?sitelink WHERE {
      ?sitelink schema:about wd:' || $id || ' .
      FILTER (regex(str(?sitelink), "[.]wikipedia[.]org"))
    }'
    let $url := $wd:sparql-endpoint || '?query=' || xmldb:encode($sparql)
    let $request :=
        <hc:request method="get" href="{ $url }">
            <hc:header name="Accept" value="application/xml" />
        </hc:request>
    let $response := hc:send-request($request)
    return
        $response[2]//sparqlres:sparql/
      sparqlres:results/sparqlres:result/sparqlres:binding/sparqlres:uri/text()
};

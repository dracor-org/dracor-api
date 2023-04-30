xquery version "3.1";

(:~
 : Module bridging dracor and wikidata.
 :)
module namespace wd = "http://dracor.org/ns/exist/v1/wikidata";

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

(:~
 : Query author information for author with given wikidata ID
 :
 : @param $id Wikidata ID (of an author)
:)
declare function wd:get-author-info($id as xs:string, $lang as xs:string*) {
    let $sparql := '
SELECT ?author ?authorLabel ?birthDate ?deathDate ?gender ?genderLabel
  ?birthPlace ?birthPlaceLabel ?birthCoord
  ?deathPlace ?deathPlaceLabel ?deathCoord
  ?img ?gnd
WHERE {
  BIND (wd:' || $id || ' AS ?author)
  OPTIONAL { ?author wdt:P569 ?birthDate. }
  OPTIONAL { ?author wdt:P570 ?deathDate. }
  OPTIONAL { ?author wdt:P21 ?gender. }
  OPTIONAL { ?author wdt:P19 ?birthPlace. }
  OPTIONAL { ?author wdt:P20 ?deathPlace. }
  #OPTIONAL { ?birthPlace wdt:P625 ?birthCoord. }
  OPTIONAL { ?author wdt:P18 ?img. }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "'
  || (if($lang) then ($lang) else "en") || '". }
}'

    let $url := $wd:sparql-endpoint || '?query=' || xmldb:encode($sparql)
    let $request :=
        <hc:request method="get" href="{ $url }">
            <hc:header name="Accept" value="application/xml" />
        </hc:request>
    let $response := hc:send-request($request)
    let $bindings := $response[2]//sparqlres:sparql/
      sparqlres:results/sparqlres:result/sparqlres:binding

    let $img := $bindings[@name="img"][1]/sparqlres:uri/text()

    return (
      map:merge((
        map:entry(
          'name', $bindings[@name="authorLabel"][1]/sparqlres:literal/text()
        ),
        map:entry(
          'genderUri', $bindings[@name="gender"][1]/sparqlres:uri/text()
        ),
        map:entry(
          'gender', $bindings[@name="genderLabel"][1]/sparqlres:literal/text()
        ),
        map:entry(
          'birthPlace',
          $bindings[@name="birthPlaceLabel"][1]/sparqlres:literal/text()
        ),
        map:entry(
          'deathPlace',
          $bindings[@name="deathPlaceLabel"][1]/sparqlres:literal/text()
        ),
        map:entry(
          'birthDate', $bindings[@name="birthDate"][1]/sparqlres:literal/text()
        ),
        map:entry(
          'deathDate', $bindings[@name="deathDate"][1]/sparqlres:literal/text()
        ),
        if($img) then map:entry('imageUrl', $img) else ()
      ))
    )
};

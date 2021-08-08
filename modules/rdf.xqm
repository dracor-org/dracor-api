xquery version "3.1";

(:~
 : DraCor RDF module
 :)
module namespace drdf = "http://dracor.org/ns/exist/v1/rdf";

import module namespace config = "http://dracor.org/ns/exist/v1/config"
  at "config.xqm";

import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: Namespaces for Linked Open Data :)
declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";
declare namespace rdfs="http://www.w3.org/2000/01/rdf-schema#" ;
declare namespace owl="http://www.w3.org/2002/07/owl#";
declare namespace dc="http://purl.org/dc/elements/1.1/";
declare namespace dracon="http://dracor.org/ontology#";
declare namespace crm="http://www.cidoc-crm.org/cidoc-crm/" ;
declare namespace schema="http://schema.org/" ;
declare namespace frbroo="http://iflastandards.info/ns/fr/frbr/frbroo/";


(: baseuri of entities :)
declare variable $drdf:baseuri := "https://dracor.org/entity/";
declare variable $drdf:typebaseuri := $drdf:baseuri || "type/";
(: baseuris of ontologies :)
declare variable $drdf:crm := "http://www.cidoc-crm.org/cidoc-crm/" ;
declare variable $drdf:dracon := "http://dracor.org/ontology#" ;
declare variable $drdf:wd := "http://www.wikidata.org/entity/" ;
declare variable $drdf:gnd := "https://d-nb.info/gnd/" ;
declare variable $drdf:viaf := "http://viaf.org/viaf/" ;

(: Refactor drdf:play-to-rdf  :)

(: Functions to generate URIs of dracor-entites :)

(:~
 : Generate an URI for the tei:author of a play
 :
 : @param $author TEI element
 :)
declare function drdf:get-author-uri($author as element(tei:author))
as xs:string
{
(:
 : construct an ID for author; default use unique Wikidata-Identifier in uri (to be discussed)
 : if not present, create some kind of fallback of md5 hash of name
 : ideally, all authors are identified by a wikidata ID! should be checked by schema
 :)


    (: hack :)
    let $dummyTEI := <tei:TEI><tei:fileDesc><tei:titleStmt>{$author}</tei:titleStmt></tei:fileDesc></tei:TEI>
    let $authorMap := dutil:get-authors($dummyTEI)
    (: if wikidata Q is present --> /entity/{Q} :)
    let $uri :=
        if ( $author//tei:idno[@type eq "wikidata"] ) then
            $drdf:baseuri ||  $author//tei:idno[@type eq "wikidata"]/string()
        else
            $drdf:baseuri || util:hash($authorMap?name ,"md5")

    return $uri
};


(: Functions to generate RDF of certain dracor-entities :)

(:~
 : Create an RDF representation of tei:author
 :
 : @param $author TEI element
 : @param $playID ID of the play entity
 : @param $lang ISO language code of play
 : @param $wrapRDF set to true if output should be wrapped in <rdf:RDF> for standalone use; false is default.

 :)
declare function drdf:author-to-rdf($author as element(tei:author), $playID as xs:string, $lang as xs:string, $wrapRDF as xs:boolean)
as element()* {

    let $authorURI := drdf:get-author-uri($author)

    (: Information-extraction from TEI would ideally be based on dutil:get-authors; but this function handles multiple authors and operates on the whole tei:TEI instead of an already extracted single author-element :)
    (: hack: send a <tei:TEI> with a single <author> – expects xpath  $tei//tei:fileDesc/tei:titleStmt/  :)
    let $dummyTEI := <tei:TEI><tei:fileDesc><tei:titleStmt>{$author}</tei:titleStmt></tei:fileDesc></tei:TEI>
    let $authorMap := dutil:get-authors($dummyTEI)

    (: generate rdfs:label/s of author :)

    let $main-rdfs-label := if ($lang != "" ) then <rdfs:label xml:lang="{$lang}">{$authorMap?name}</rdfs:label> else <rdfs:label>{$authorMap?name}</rdfs:label>

    let $en-rdfs-label := if ( map:contains($authorMap, "shortnameEn") ) then <rdfs:label xml:lang="eng">{$authorMap?nameEn}</rdfs:label> else false()

    (: appellations :)

    (: use generic function to generate appellations of certain type :)
    (: appellations to generate: name, fullname, fullnameEn, shortname, shortnameEn :)
    (: todo: $lang is not evaluated :)
    let $appellationTypes := ("name", "fullname", "fullnameEn", "shortname", "shortnameEn" )
    let $appellations := for $nameType in $appellationTypes return
        if ( map:contains($authorMap, $nameType) )
        then drdf:generate-crm-appellation($authorURI, $nameType, map:get($authorMap,$nameType), $lang, false() )
        else ()

    (: todo: shortname, shortnameEn should be the same appellation type, maybe :)
    (: todo: handle alsoKnownAs (Pseudonym,...) – see schema :)


    (: Link author and play according to dracor ontology :)
    let $is-author-of := <dracon:is_author_of rdf:resource="{$drdf:baseuri}{$playID}"/>


    (: add links to external reference resources as owl:sameAs statements :)
    (: can handle wikidata, gnd/pnd and viaf :)
    (: this somehow duplicates the functionality of dutil:get-authors, which would return an array of refs but operates on the whole tei:TEI instead of a single author :)
    let $sameAs :=
        for $refMap in $authorMap?refs?* return

            switch($refMap?type)
                case "wikidata" return <owl:sameAs rdf:resource="{$drdf:wd}{$refMap?ref}"/>
                case "pnd" return <owl:sameAs rdf:resource="{$drdf:gnd}{$refMap?ref}"/>
                case "viaf" return <owl:sameAs rdf:resource="{$drdf:viaf}{$refMap?ref}"/>
                default return ()

    (: generated RDF follows :)
    let $generatedRDF :=
        (

        (: Author related triples :)
        <rdf:Description rdf:about="{$authorURI}">
            <rdf:type rdf:resource="{$drdf:crm}E21_Person"/>
            <rdf:type rdf:resource="{$drdf:dracon}author"/>
            {if ($main-rdfs-label) then $main-rdfs-label else ()}
            {if ($en-rdfs-label) then $en-rdfs-label else () }
            {$is-author-of}
            {if ($sameAs) then $sameAs else ()}
        </rdf:Description>
        , (: important!:)

        (: appellations and their connections :)
        $appellations
        )

    return
        (: maybe should switch here on param $wrapRDF :)
        $generatedRDF

};

(:~
 : Create a CIDOC appellation of a certain type
 :
 : @param $entityUri URI of the entity
 : @param $type of the appellation
 : @param $value String-Value of the appellation
 : @param $language of the Value of the appellation
 : @param $wrapRDF wrap with rdf:RDF?
 :  :)
declare function drdf:generate-crm-appellation($entityUri as xs:string, $type as xs:string, $value as xs:string, $lang as xs:string, $wrapRDF as xs:boolean )
as element()* {

    (: todo: handle language parameter :)
    (: shortname and shortnameEn shound be the same type, but in different language :)

    let $appellationUri := $entityUri || "/appellation/" || $type
    let $appellationTypeUri := $drdf:typebaseuri || $type

    let $appellationRDF :=
        <rdf:Description rdf:about="{$appellationUri}">
            <rdf:type rdf:resource="{$drdf:crm}E41_Appellation"/>
            <rdfs:label>{$value} [appellation; {$type}]</rdfs:label>
            <crm:P2_has_type rdf:resource="{$appellationTypeUri}"/>
            <crm:P1i_identifies rdf:resource="{$entityUri}"/>
            <rdf:value>{$value}</rdf:value>
        </rdf:Description>

    let $link :=
        <rdf:Description rdf:about="{$entityUri}">
            <crm:P1_is_identified_by rdf:resource="{$appellationUri}"/>
        </rdf:Description>

    let $generatedRDF :=
        ( $appellationRDF, $link )

    return $generatedRDF
};

(:~
 : Get Uri of a play
 : @param $play TEI Element
 :)
declare function drdf:get-play-uri($play as element(tei:TEI) )
as xs:string {
    (:reuse dutil function :)
    $drdf:baseuri || dutil:get-dracor-id($play)
};

(:~
 : Cidoc style titles
 : @param $entityUri URI of the (play) entity
 : @param $type of the appellation
 : @param $value String-Value of the appellation
 : @param $language of the Value of the appellation
 : @param $wrapRDF wrap with rdf:RDF?
 :)
declare function drdf:generate-crm-title($entityUri as xs:string, $type as xs:string, $value as xs:string, $lang as xs:string, $wrapRDF as xs:boolean)
as element()* {
    let $title-uri := $entityUri || "/title/" || $type || "/" || $lang

    let $titleRDF :=
    <rdf:Description rdf:about="{$title-uri}">
        <rdf:type rdf:resource="{$drdf:crm}E35_Title"/>
        <rdfs:label>{$value} [{$type}{if ($type eq "sub") then () else " "}title]</rdfs:label>
        <crm:P2_has_type rdf:resource="{$drdf:typebaseuri || 'title/' || $type}"/>
        <crm:P102i_is_title_of rdf:resource="{$entityUri}"/>
        <crm:P72_has_language rdf:resource="{$drdf:baseuri}language/{$lang}"/>
        <rdf:value>{$value}</rdf:value>
    </rdf:Description>

    let $link := <rdf:Description rdf:about="{$entityUri}">
            <crm:P102_has_title rdf:resource="{$title-uri}"/>
        </rdf:Description>

    return ($titleRDF , $link)

};

(:~
 : Create an RDF representation of a play.
 :
 : @param $play TEI element
 : @author Ingo Börner
 : @author Carsten Milling
 :)
declare function drdf:play-to-rdf ($play as element(tei:TEI))
as element(rdf:RDF) {
  let $paths := dutil:filepaths($play/base-uri())
  let $corpusname := $paths?corpusname
  let $playname := $paths?playname
  let $metricspath := $paths?files?metrics
  let $metrics := doc($metricspath)
  let $lang := $play/@xml:lang/string()

  let $play-uri := drdf:get-play-uri($play)

  (: Titles, ... :)
  let $defaultLanguageTitlesMap := dutil:get-titles($play)
  let $engTitlesMap := dutil:get-titles($play, "eng")

  let $defaultTitleString := if ( map:contains($defaultLanguageTitlesMap, "sub") )
        then ( $defaultLanguageTitlesMap?main, if ( matches($defaultLanguageTitlesMap?main, "[!?.]$") ) then "" else ".", " ", $defaultLanguageTitlesMap?sub ) => string-join("")
        else $defaultLanguageTitlesMap?main

    let $engTitleString := if ( map:contains($engTitlesMap, "main" ) ) then
        if ( map:contains($engTitlesMap, "sub") )
        then ( $engTitlesMap?main, if ( matches($engTitlesMap?main, "[!?.]$") ) then "" else ".", " ", $engTitlesMap?sub ) => string-join("")
        else $engTitlesMap?main
    else "" (: no english titles:)

  (: build dc:title Elements :)
  let $dc-titles := (
        <dc:title xml:lang="{$lang}">{$defaultTitleString}</dc:title> ,
        if ($engTitleString != "" and $lang != "eng" ) then <dc:title xml:lang="eng">{$engTitleString}</dc:title> else ()
    )

  (: Get the map(s) containing metadata on the authors :)
  let $authors := dutil:get-authors($play)

  (: create rdfs-label from author and title data :)
  let $default-rdfs-label-string := $authors?name => string-join(" / ") || ": " || $defaultTitleString
  let $default-rdfs-label := <rdfs:label xml:lang="{$lang}">{$default-rdfs-label-string}</rdfs:label>

  (: create english rdfs:label :)
  let $eng-rdfs-label-string := if (map:contains($authors[1], "nameEn")) then $authors?nameEn => string-join(" / ") || ": " || $engTitleString else ""
  let $eng-rdfs-label := if ($eng-rdfs-label-string != "" and $lang != "eng" ) then <rdfs:label xml:lang="eng">{$eng-rdfs-label-string}</rdfs:label> else ()

  (: CIDOC: E33_Linguistic_Object P102_has_title E35_Title :)
  (: uri-pattern https://dracor.org/entity/ger000165/title/main/ger, https://dracor.org/entity/ger000165/title/sub/ger, ...   :)

  let $titleTypes := ("main", "sub")
  let $default-crm-title-elements := for $titleItem in $titleTypes return drdf:generate-crm-title($play-uri, $titleItem, map:get($defaultLanguageTitlesMap,$titleItem), $lang, false())
  let $eng-crm-title-elements := if ( map:contains($engTitlesMap, "main" ) ) then  for $titleItem in $titleTypes return drdf:generate-crm-title($play-uri, $titleItem, map:get($engTitlesMap,$titleItem), "eng", false()) else ()

  (: dc:creators :)
  (: maybe include english creator-elements :)
  let $dc-creators := for $author in $authors return <dc:creator xml:lang="{$lang}">{$author?name}</dc:creator>


  (: build main RDF Chunk :)
  let $inner :=
    <rdf:Description rdf:about="{$play-uri}">
      <rdf:type rdf:resource="{$drdf:crm}E33_Linguistic_Object"/>
      <rdf:type rdf:resource="{$drdf:dracon}play"/>
      {$default-rdfs-label}
      {$eng-rdfs-label}
      {$dc-titles}
      {$dc-creators}
    </rdf:Description>


  return
    <rdf:RDF
      xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      xmlns:owl="http://www.w3.org/2002/07/owl#"
      xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
      xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:dracon="http://dracor.org/ontology#"
      xmlns:crm="http://www.cidoc-crm.org/cidoc-crm/"
      xmlns:xsd="http://www.w3.org/2001/XMLSchema#"
      xmlns:schema="http://schema.org/"
      xmlns:frbroo="http://iflastandards.info/ns/fr/frbr/frbroo/"
    >
    {$inner}
    {$default-crm-title-elements}
    {$eng-crm-title-elements}
    </rdf:RDF>


};
(:~
 : Update RDF for single play
 :
 : @param $url URL of the TEI document
:)
declare function drdf:update($url as xs:string) {
  let $rdf := drdf:play-to-rdf(doc($url)/tei:TEI)
  let $paths := dutil:filepaths($url)
  let $collection := $paths?collections?rdf
  let $resource := $paths?playname || ".rdf.xml"
  return (
    util:log('info', ('RDF update: ', $collection, "/", $resource)),
    xmldb:store($collection, $resource, $rdf) => xs:anyURI() => drdf:fuseki()
  )
};

(:~
 : Update RDF for all plays in the database
:)
declare function drdf:update() as xs:string* {
  let $l := util:log-system-out("Updating RDF files")
  for $tei in collection($config:data-root)//tei:TEI
  let $url := $tei/base-uri()
  return drdf:update($url)
};

declare function drdf:fuseki-clear-graph($corpusname as xs:string) {
  let $url := $config:fuseki-server || "update"
  let $graph := "http://dracor.org/" || $corpusname
  let $log := util:log-system-out("clearing fuseki graph: " || $graph)
  let $request :=
    <hc:request
      method="post"
      username="admin"
      password="{$config:fuseki-pw}"
      auth-method="basic"
      send-authorization="true"
    >
      <hc:body media-type="application/sparql-update" method="text">
        CLEAR SILENT GRAPH &lt;{$graph}&gt;
      </hc:body>
    </hc:request>

  let $response := hc:send-request($request, $url)

  return if ($response/@status = "204") then (
    util:log-system-out("Cleared graph <" || $graph || ">"),
    true()
  ) else (
    util:log-system-out(
      "Failed to clear graph <" || $graph || ">: " || $response/message
    ),
    false()
  )
};

(:~
 : Send RDF data to Fuseki
 https://github.com/dracor-org/dracor-api/issues/77
 :)
declare function drdf:fuseki($uri as xs:anyURI) {
  let $corpus := tokenize($uri, "/")[position() = last() - 1]
  let $url := $config:fuseki-server || "data" || "?graph=" || encode-for-uri("http://dracor.org/" || $corpus)
  let $rdf := doc($uri)
  let $request :=
    <hc:request method="post" href="{ $url }">
      <hc:body media-type="application/rdf+xml">{ $rdf }</hc:body>
    </hc:request>
  let $response :=
      hc:send-request($request)
  let $status := string($response[1]/@status)
  return
      switch ($status)
          case "200" return true()
          case "201" return true()
          default return (
              util:log("info", "unable to store to fuseki: " || $uri),
              util:log("info", "response header from fuseki: " || $response[1]),
              util:log("info", "response body from fuseki: " || $response[2]))
};

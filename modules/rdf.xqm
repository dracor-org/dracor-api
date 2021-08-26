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
declare variable $drdf:sitebase := "https://dracor.org/";
declare variable $drdf:baseuri := "https://dracor.org/entity/";
declare variable $drdf:typebaseuri := $drdf:baseuri || "type/";
declare variable $drdf:corpusbaseuri := $drdf:baseuri || "corpus/";
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
 : @param $playUri URI of the play entity
 : @param $lang ISO language code of play
 : @param $wrapRDF set to true if output should be wrapped in <rdf:RDF> for standalone use; false is default.

 :)
declare function drdf:author-to-rdf($author as element(tei:author), $playUri as xs:string, $lang as xs:string, $wrapRDF as xs:boolean)
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
    let $is-author-of := <dracon:is_author_of rdf:resource="{$playUri}"/>


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
 : Uri of an character of a play
 : @param $play-uri URI of the play
 : @param $character-id ID of the character used in xml:id and @who in the TEI representation
 :)
declare function drdf:get-character-uri($play-uri as xs:string, $character-id as xs:string)
as xs:string {
    $play-uri || '/character/' || $character-id
};


(:~
 : Metrics of a play as RDF
 : @param $corpusname
 : @param $playname
 : @param $playuri URI of the play
 : @param $wrapRDF wrap with rdf:RDF?
 :)
declare function drdf:play-metrics-to-rdf($corpusname as xs:string, $playname as xs:string, $playuri as xs:string, $wrapRDF as xs:boolean)
as element()* {
    let $metrics := dutil:get-play-metrics($corpusname, $playname)
    (: which metrics are computed? :)
    (:
    "size": 4.9e1,
    "averageClustering": 8.497673123239153e-1, --> implemented
    "density": 3.129251700680272e-1, --> implemented
    "averagePathLength": 1.751700680272109e0, --> implemented
    "maxDegreeIds": ["muenzer"],
    "corpus": "ger", --> irrelevant
    "averageDegree": 1.5020408163265307e1, --> implemented
    "name": "alberti-brot", --> irrelevant
    "diameter": 3.0e0, --> implemented
    "maxDegree": 4.0e1, --> implemented
    "numConnectedComponents": 1.0e0, --> implemented
    "id": "ger000171", --> irrelevant
    "wikipediaLinkCount": 0
    :)

    (: for each character, there are metrics, that are included in an array with the key   "nodes": which contains maps :)
    (:
    map {
        "weightedDegree": 7.6e1,
        "degree": 2.8e1,
        "closeness": 7.058823529411765e-1,
        "eigenvector": 2.2702062167043066e-1,
        "id": "blinte",
        "betweenness": 2.1865702380953058e-2
    :)

    (: datatypes see https://www.w3.org/TR/xmlschema-2/ :)

    let $averageClustering :=
        if ( map:contains($metrics, "averageClustering") ) then
        <dracon:averageClustering rdf:datatype="http://www.w3.org/2001/XMLSchema#decimal">
          {$metrics?averageClustering}
        </dracon:averageClustering>
        else ()


    let $averagePathLength :=
        if ( map:contains($metrics, "averagePathLength") ) then
        <dracon:averagePathLength rdf:datatype="http://www.w3.org/2001/XMLSchema#decimal">
          {$metrics?averagePathLength}
        </dracon:averagePathLength>
        else ()

    let $averageDegree :=
        if ( map:contains($metrics, "averageDegree") ) then
        <dracon:averageDegree rdf:datatype="http://www.w3.org/2001/XMLSchema#decimal">
            {$metrics?averageDegree}
        </dracon:averageDegree>
        else ()

    let $density :=
        if ( map:contains($metrics, "density") ) then
        <dracon:density rdf:datatype="http://www.w3.org/2001/XMLSchema#decimal">
          {$metrics?density}
        </dracon:density>
        else ()

    let $diameter :=
        if ( map:contains($metrics, "diameter") ) then
        <dracon:diameter rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {$metrics?diameter}
        </dracon:diameter>
        else ()

    let $maxDegree :=
        if ( map:contains($metrics, "maxDegree") ) then
        <dracon:maxDegree rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {$metrics?maxDegree}
        </dracon:maxDegree>
        else ()

    (: missing in dracon: "size"?, "numConnectedComponents", wikipediaLinkCount"  :)

    let $networkSize :=
        if ( map:contains($metrics, "size") ) then
            <dracon:networkSize rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                {$metrics?size}
            </dracon:networkSize>
        else ()

    let $numConnectedComponents :=
        if ( map:contains($metrics, "numConnectedComponents") ) then
            <dracon:numConnectedComponents rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                {$metrics?numConnectedComponents}
            </dracon:numConnectedComponents>
        else ()

    let $wikipediaLinkCount :=
        if ( map:contains($metrics, "wikipediaLinkCount") ) then
            <dracon:wikipediaLinkCount rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                {$metrics?wikipediaLinkCount}
            </dracon:wikipediaLinkCount>
        else ()


    (: use array "maxDegreeIds" to construct triples of maxDegree-Character :)
    let $maxDegreeCharacters :=
        if ( map:contains($metrics, "maxDegreeIds") ) then
            for $character-id in $metrics?maxDegreeIds?*
                let $character-uri := drdf:get-character-uri($playuri, $character-id)
                return <dracon:maxDegreeCharacter rdf:resource="{$character-uri}"/>
        else ()

    (: network-metrics of the single character, that are included in the map "nodes" :)
    let $character-network-metrics :=
        if ( map:contains($metrics , "nodes" )  ) then
            for $character-map in $metrics?nodes?*
                let $character-id := $character-map?id
                let $character-uri := drdf:get-character-uri($playuri, $character-id)
                (:
                "weightedDegree": 1.4e1,
                "degree": 9.0e0,
                "closeness": 5.333333333333333e-1,
                "eigenvector": 8.233954138362518e-2,
                :)

                let $character-degree :=
                    if ( map:contains($character-map, "degree") ) then
                        <dracon:degree rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                            {$character-map?degree}
                        </dracon:degree>
                    else ()

                let $character-weightedDegree :=
                    if ( map:contains($character-map, "weightedDegree") ) then
                        <dracon:weightedDegree rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                            {$character-map?weightedDegree}
                        </dracon:weightedDegree>
                    else ()

                let $character-closeness :=
                    if ( map:contains($character-map, "closeness") ) then
                        <dracon:closeness rdf:datatype="http://www.w3.org/2001/XMLSchema#decimal">
                            {$character-map?closeness}
                        </dracon:closeness>
                    else ()

                let $character-eigenvector :=
                    if ( map:contains($character-map, "eigenvector") ) then
                        <dracon:eigenvector rdf:datatype="http://www.w3.org/2001/XMLSchema#decimal">
                            {$character-map?eigenvector}
                        </dracon:eigenvector>
                    else ()


                return
                    <rdf:Description rdf:about="{$character-uri}">
                        {$character-degree}
                        {$character-weightedDegree}
                        {$character-closeness}
                        {$character-eigenvector}
                    </rdf:Description>

        else () (: no map-key "nodes" :)



    let $playRDF :=
        <rdf:Description rdf:about="{$playuri}">
            {$averageClustering}
            {$averagePathLength}
            {$averageDegree}
            {$density}
            {$diameter}
            {$maxDegree}
            {$networkSize}
            {$numConnectedComponents}
            {$wikipediaLinkCount}
            {$maxDegreeCharacters}
        </rdf:Description>

    let $charactersRDF :=
        $character-network-metrics

    return
        ( $playRDF , $charactersRDF)
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
  let $lang := $play/@xml:lang/string()

  let $play-uri := drdf:get-play-uri($play)

  let $play-info := dutil:get-play-info($corpusname, $playname)

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

  (: author-nodes :)
  (: uses the tei:author elements, not the author-map :)
  let $author-rdf := for $author in $play//tei:titleStmt//tei:author return drdf:author-to-rdf($author, $play-uri, $lang, false())

  (: creation-activity to connect author and play CIDOC like :)
  (: todo :)

  (: Link of web-representation :)
  let $dracor-url := $drdf:sitebase || $paths?corpusname || "/" || $paths?playname
  let $dracor-link :=
      <rdfs:seeAlso rdf:resource="{$dracor-url}"/>

  (: parent corpus :)
  let $parent-corpus-uri := $drdf:corpusbaseuri || $paths?corpusname
  let $in_corpus := <dracon:in_corpus rdf:resource="{$parent-corpus-uri}"/>

  (: network-metrics – wrapper for dutil:get-play-metrics($corpusname, $playname) :)
  (: includes triples for network-metrics of play and it's character-nodes :)
  let $network-metrics := drdf:play-metrics-to-rdf($corpusname, $playname, $play-uri, false())

  (: dates can be retrieved either from the play-info map generated or dutil:get-years-iso($tei); $play-info is available at this point :)
  (: "yearWritten": "1888", xs:string, "yearPremiered": (),
    "yearPrinted": "1888", xs:string :)
    (: "yearNormalized": xs:integer(dutil:get-normalized-year($tei)) is cast to an integer! not xs:string or empty sequence! :)
    (:
     <owl:DatatypeProperty rdf:about="http://dracor.org/ontology#normalisedYear">
     <rdfs:range rdf:resource="http://www.w3.org/2001/XMLSchema#gYear"/>

      <owl:DatatypeProperty rdf:about="http://dracor.org/ontology#premiereYear">
      <owl:DatatypeProperty rdf:about="http://dracor.org/ontology#printYear">
      <owl:DatatypeProperty rdf:about="http://dracor.org/ontology#writtenYear">
    :)

    let $writtenYear :=
        if ( map:contains($play-info, "yearWritten") ) then
            if ( $play-info?yearWritten ) then
                <dracon:writtenYear rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
                    {$play-info?yearWritten}
                </dracon:writtenYear>
            else ()
        else ()

    let $printYear :=
        if ( map:contains($play-info, "yearPrinted") ) then
            if ( $play-info?yearPrinted ) then
                <dracon:printYear rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
                    {$play-info?yearPrinted}
                </dracon:printYear>
            else ()
        else ()


    let $premiereYear :=
        if ( map:contains($play-info, "yearPremiered") ) then
                if ( $play-info?yearPremiered ) then
                <dracon:premiereYear rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
                    {$play-info?yearPremiered}
                </dracon:premiereYear>
                else ()
        else ()

        (: normalized year :)
    let $normalisedYear :=
        if ( map:contains($play-info, "yearNormalized") ) then
            if ( $play-info?yearNormalized ) then
                <dracon:normalisedYear rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
                    {$play-info?yearNormalized}
                </dracon:normalisedYear>
                else ()
        else ()

    (: dutil:get-play-info($corpusname, $playname) provides some additional metrics :)
    (: "allInIndex" :)
    (: "allInSegment" should point to a segment :)

    (: wikidata-id of the play: "wikidataId": "Q51370104", :)
    let $sameAs-wikidata :=
        if ( map:contains($play-info, "wikidataId") ) then
            <owl:sameAs rdf:resource="{$drdf:wd || $play-info?wikidataId}"/>
        else ()
    (: should add external identifiers via crm:identified by... :)


    (: "originalSource" :)
    (: maybe use dc:source :)
    let $dc-source :=
        if ( map:contains($play-info, "originalSource") ) then
            <dc:source>{$play-info?originalSource}</dc:source>
        else ()



  (: these metrics have to be retrieved by separate util-function :)
  let $numOfActs :=
        <dracon:numOfActs rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
            {()}
        </dracon:numOfActs>

    (: will count the segments in $play-info :)
    (: there seems to be no dutil:function to retrieve this value :)
    let $numOfSegments :=
        if ( map:contains($play-info, "segments") ) then
            let $segmentCnt := count($play-info?segments?*)
            return
                <dracon:numOfSegments rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                    {$segmentCnt}
                </dracon:numOfSegments>
        else ()

    let $numOfSpeakers :=
        <dracon:numOfSpeakers rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {()}
        </dracon:numOfSpeakers>

    (: segments :)
    (: todo :)

    (: cast :)
    (: todo :)

  (: build main RDF Chunk :)
  let $inner :=
    <rdf:Description rdf:about="{$play-uri}">
      <rdf:type rdf:resource="{$drdf:crm}E33_Linguistic_Object"/>
      <rdf:type rdf:resource="{$drdf:dracon}play"/>
      {$default-rdfs-label}
      {$eng-rdfs-label}
      {$dc-titles}
      {$dc-creators}
      {$dc-source}
      {$dracor-link}
      {$in_corpus}
      {$writtenYear}
      {$printYear}
      {$premiereYear}
      {$normalisedYear}
      {$numOfSegments}
      {$sameAs-wikidata}
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
    {$author-rdf}
    {$network-metrics}
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

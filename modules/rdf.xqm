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
declare variable $drdf:datebaseuri := $drdf:baseuri || "date/";
declare variable $drdf:activitybaseuri := $drdf:baseuri || "activity/";
declare variable $drdf:relationtypebaseuri := $drdf:typebaseuri || "relation/";
declare variable $drdf:genretypebaseuri := $drdf:typebaseuri || "genre/";
declare variable $drdf:corpusbaseuri := $drdf:baseuri || "corpus/";
declare variable $drdf:relationbaseuri := $drdf:baseuri || "relation/";
(: baseuris of ontologies :)
declare variable $drdf:crm := "http://www.cidoc-crm.org/cidoc-crm/" ;
declare variable $drdf:dracon := "http://dracor.org/ontology#" ;
declare variable $drdf:wd := "http://www.wikidata.org/entity/" ;
declare variable $drdf:gnd := "https://d-nb.info/gnd/" ;
declare variable $drdf:viaf := "http://viaf.org/viaf/" ;
declare variable $drdf:frbroo := "http://iflastandards.info/ns/fr/frbr/frbroo/" ;

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

    (: Wikidata-Identifier also cidoc-appellation-style :)
    (: maybe add this functionality to more generic id generation function :)
    let $wd := for $refMap in $authorMap?refs?* where $refMap?type eq "wikidata" return $refMap?ref
    let $wd-identifier-uri := $authorURI || "/id/wikidata"
    let $wd-identifier-label := "Wikidata Identifier of " || $authorMap?name
    let $wd-identifier-triples :=
        if ( $wd != "" or $wd != () ) then
            drdf:cidoc-identifier($wd-identifier-uri, "wikidata", $wd-identifier-label , $authorURI, $wd)
        else ()

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
        $appellations,
        $wd-identifier-triples
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
        <dracon:averageClustering rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
          {$metrics?averageClustering}
        </dracon:averageClustering>
        else ()


    let $averagePathLength :=
        if ( map:contains($metrics, "averagePathLength") ) then
        <dracon:averagePathLength rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
          {$metrics?averagePathLength}
        </dracon:averagePathLength>
        else ()

    let $averageDegree :=
        if ( map:contains($metrics, "averageDegree") ) then
        <dracon:averageDegree rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
            {$metrics?averageDegree}
        </dracon:averageDegree>
        else ()

    let $density :=
        if ( map:contains($metrics, "density") ) then
        <dracon:density rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
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
                (: betweenness might be missing :)

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
                        <dracon:closeness rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
                            {$character-map?closeness}
                        </dracon:closeness>
                    else ()

                let $character-eigenvector :=
                    if ( map:contains($character-map, "eigenvector") ) then
                        <dracon:eigenvector rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
                            {$character-map?eigenvector}
                        </dracon:eigenvector>
                    else ()

                let $character-betweenness :=
                    if ( map:contains($character-map, "betweenness") ) then
                        <dracon:betweenness rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
                            {$character-map?betweenness}
                        </dracon:betweenness>
                    else ()


                return
                    <rdf:Description rdf:about="{$character-uri}">
                        {$character-degree}
                        {$character-weightedDegree}
                        {$character-closeness}
                        {$character-eigenvector}
                        {$character-betweenness}
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
 : Characters of a play as RDF
 : @param $corpusname
 : @param $playname
 : @param $playtitle Title of play (will be added to rdfs:label). If empty string, no additional text will be added to label
 : @param $playuri URI of the play
 : @param $includeMetrics should be set to true if network metrics of characters should be included; default true
 : @param $wrapRDF wrap with rdf:RDF?
 :)

declare function drdf:characters-to-rdf($corpusname as xs:string, $playname as xs:string, $playtitle as xs:string, $playuri as xs:string, $includeMetrics as xs:boolean , $wrapRDF as xs:boolean)
as element()* {
    let $cast := dutil:cast-info($corpusname, $playname)
    let $characters :=
        for $character-map in $cast?*
        let $character-uri := drdf:get-character-uri($playuri, $character-map?id)
        (:
        "numOfSpeechActs": 68, --> implemented
        "gender": "MALE", / "FEMALE" / "UNKNOWN" --> implemented
        "name": Dietrich,
    "numOfWords": 1580, --> implemented
    "isGroup": false(), --> implemented
    "numOfScenes": 1, --> implemented
    "id": "dietrich",
    Wikidata --> implemented
        :)

        let $rdfs-label :=
            if ( map:contains($character-map, "name") ) then
                <rdfs:label>{$character-map?name}{ if ($playtitle != "") then " [Character in '" || $playtitle || "']" else ""}</rdfs:label>
            else ()

        let $gender :=
            if ( map:contains($character-map, "gender") ) then
                let $gendertype := $drdf:typebaseuri || "gender/" || lower-case($character-map?gender) return
                <crm:P2_has_type rdf:resource="{$gendertype}"/>
            else ()

        let $hasGroupType :=
            if ( map:contains($character-map, "isGroup") ) then
                if ( $character-map?isGroup ) (:true():) then
                    let $groupType := $drdf:typebaseuri || "group"
                    return <crm:P2_has_type rdf:resource="{$groupType}"/>
                else ()
            else ()

        let $character-in := <dracon:is_character_in rdf:resource="{$playuri}"/>
        let $has-character := <dracon:has_character rdf:resource="{$character-uri}"/>

        let $based-on-wikidata :=
            if ( map:contains($character-map, "wikidataId") ) then
                <frbroo:R57_is_based_on rdf:resource="{$drdf:wd}{$character-map?wikidataId}"/>
            else ()

        let $speaks_numOfWords :=
            if ( map:contains($character-map, "numOfWords") ) then
                <dracon:speaks_numOfWords rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                    {$character-map?numOfWords}
                </dracon:speaks_numOfWords>
            else ()

        let $has_numOfSpeechActs :=
            if ( map:contains($character-map, "numOfSpeechActs") ) then
                <dracon:has_numOfSpeechActs rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                    {$character-map?numOfSpeechActs}
                </dracon:has_numOfSpeechActs>
            else ()

        let $in_numOfScenes :=
            if ( map:contains($character-map, "numOfScenes") ) then
                <dracon:in_numOfScenes rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
                    {$character-map?numOfScenes}
                </dracon:in_numOfScenes>
            else ()

            let $character-appellation-uri := $character-uri || "/appellation/" || "1"

            let $identified_by_appellation :=
                if (map:contains($character-map, "name") ) then
                    <crm:P1_is_identified_by rdf:resource="{$character-appellation-uri}"/>
                else ()


            let $appellation-node :=
                if (map:contains($character-map, "name") ) then
                    <rdf:Description rdf:about="{$character-appellation-uri}">
                        <rdf:type rdf:resource="{$drdf:crm}E41_Appellation"/>
                        <rdfs:label>{$character-map?name} [appellation of character]</rdfs:label>
                        <crm:P1i_identifies rdf:resource="{$character-uri}"/>
                        <rdf:value>{$character-map?name}</rdf:value>
                    </rdf:Description>
                else ()




        (: metrics :)
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
                        <dracon:closeness rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
                            {$character-map?closeness}
                        </dracon:closeness>
                    else ()

                let $character-eigenvector :=
                    if ( map:contains($character-map, "eigenvector") ) then
                        <dracon:eigenvector rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
                            {$character-map?eigenvector}
                        </dracon:eigenvector>
                    else ()

               let $character-betweenness :=
                    if ( map:contains($character-map, "betweenness") ) then
                        <dracon:betweenness rdf:datatype="http://www.w3.org/2001/XMLSchema#float">
                            {$character-map?betweenness}
                        </dracon:betweenness>
                    else ()


        return
            (
            <rdf:Description rdf:about="{$character-uri}">
                <rdf:type rdf:resource="{$drdf:frbroo}F38_Character"/>
                <rdf:type rdf:resource="{$drdf:dracon}character"/>
                {$rdfs-label}
                {$identified_by_appellation}
                {$gender}
                {$hasGroupType}
                {if ( $includeMetrics ) then $character-degree else ()}
                {if ( $includeMetrics ) then $character-weightedDegree else ()}
                {if ( $includeMetrics ) then $character-closeness else ()}
                {if ( $includeMetrics ) then $character-eigenvector else ()}
                {if ( $includeMetrics ) then $character-betweenness else ()}
                {$speaks_numOfWords}
                {$has_numOfSpeechActs}
                {$in_numOfScenes}
                {$character-in}
                {$based-on-wikidata}
            </rdf:Description> ,
            <rdf:Description rdf:about="{$playuri}">
             {$has-character}
            </rdf:Description>
            ,
            $appellation-node
            )

    return $characters
};

(:~
 : Transform array of segments generated by dutil:play-info to rdf
 :
 : @param $segments array of maps containing info on segments
 : @param $playuri URI of the play
 : @param $playtitle Title of the play
 : :)
declare function drdf:segments-to-rdf($segments as array(map()), $playuri as xs:string, $playtitle as xs:string )
as element()*{
    (: "number": 1,
    "speakers": ["dietrich","helldrungen","erich"],
    "title": "I. Akt. | 1. Scene.",
    "type": "scene" :)
    for $segment-map in $segments?*

        let $segment-uri := $playuri || "/segment/" || xs:string($segment-map?number)
        let $segmentTypeUri := $drdf:typebaseuri || "segment/" || $segment-map?type

        let $speakers :=
            if ( map:contains($segment-map, "speakers") ) then
                for $speaker-id in $segment-map?speakers?*
                    let $speaker-uri := drdf:get-character-uri($playuri, $speaker-id)
                    let $speaker-in-segment :=
                        <rdf:Description rdf:about="{$speaker-uri}">
                            <dracon:appears_in_segment rdf:resource="{$segment-uri}"/>
                        </rdf:Description>
                    let $segment-has-speaker :=
                        <rdf:Description rdf:about="{$segment-uri}">
                            <dracon:has_speaker rdf:resource="{$speaker-uri}"/>
                        </rdf:Description>
                    return
                        ( $speaker-in-segment, $segment-has-speaker )

            else ()

        let $segment-rdf :=
            <rdf:Description rdf:about="{$segment-uri}">
                <rdf:type rdf:resource="{$drdf:crm}E33_Linguistic_Object"/>
                <rdf:type rdf:resource="{$drdf:dracon}segment"/>
                <rdfs:label>{$segment-map?title} [Segment in '{$playtitle}']</rdfs:label>
                <crm:P2_has_type rdf:resource="{$segmentTypeUri}"/>
                <crm:P106i_forms_part_of rdf:resource="{$playuri}"/>
                <dracon:is_segment_of rdf:resource="{$playuri}"/>
            </rdf:Description>

        let $linked-play :=
            <rdf:Description rdf:about="{$playuri}">
                <crm:P106_is_composed_of rdf:resource="{$segment-uri}"/>
                <dracon:has_segment rdf:resource="{$segment-uri}"/>
            </rdf:Description>

        return ($segment-rdf , $linked-play, $speakers)


};

(:~
 : Transform array of relations generated by dutil:play-info to rdf
 :
 : @param $relations array of maps containing info on segments
 : @param $playuri URI of the play
 : :)
declare function drdf:relations-to-rdf($relations as array(map()), $playuri as xs:string ) {
    (:  Possible values for the relation parameter are:
 :  - siblings
 :  - friends
 :  - spouses
 :  - parent_of_active
 :  - lover_of_active
 :  - related_with_active
 :  - associated_with_active
 :  - parent_of_passive
 :  - lover_of_passive
 :  - related_with_passive
 :  - associated_with_passive :)
 for $relation-map in $relations?* return
     let $source-uri := drdf:get-character-uri($playuri, $relation-map?source)
     let $target-uri := drdf:get-character-uri($playuri, $relation-map?target)
     let $relations :=
        switch ( $relation-map?type )
        (: spouses: mutual relation of active and passive has_spouse, is_spouse_of :)
        case "spouses" return
            let $relation-type-uri := $drdf:relationtypebaseuri || "has_spouse"
            let $relation-type-uri-inverse := $drdf:relationtypebaseuri || "is_spouse_of"
            return
                (
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri, $relation-map?source || " has spouse " || $relation-map?target) ,
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri-inverse, $relation-map?target || " is spouse of " || $relation-map?source),
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri, $relation-map?target || " has spouse " || $relation-map?source),
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri-inverse, $relation-map?source || " is spouse of " || $relation-map?target)
                )
        (: siblings :)
        (: mutual :)
        case "siblings" return
            let $relation-type-uri := $drdf:relationtypebaseuri || "has_sibling"
            let $relation-type-uri-inverse := $drdf:relationtypebaseuri || "is_sibling_of"
            return
                (
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri, $relation-map?source || " has sibling " || $relation-map?target) ,
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri-inverse, $relation-map?target || " is sibling of " || $relation-map?source),
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri, $relation-map?target || " has sibling " || $relation-map?source),
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri-inverse, $relation-map?source || " is sibling of " || $relation-map?target)
                )

        (: friends :)
        case "friends" return
            let $relation-type-uri := $drdf:relationtypebaseuri || "has_friend"
            let $relation-type-uri-inverse := $drdf:relationtypebaseuri || "is_friend_of"
            return
                (
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri, $relation-map?source || " has friend " || $relation-map?target) ,
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri-inverse, $relation-map?target || " is friend of " || $relation-map?source),
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri, $relation-map?target || " has friend " || $relation-map?source),
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri-inverse, $relation-map?source || " is friend of " || $relation-map?target)
                )

        (: lover :)
        (: consider lover_of/has_lover mutual relations :)
        (: but subject to discussion .. :)
        case "lover_of" return
            let $relation-type-uri := $drdf:relationtypebaseuri || "is_lover_of"
            let $relation-type-uri-inverse := $drdf:relationtypebaseuri || "has_lover"
            return
                (
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri, $relation-map?source || " is lover of " || $relation-map?target) ,
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri-inverse, $relation-map?target || " has lover " || $relation-map?source),
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri, $relation-map?target || " is lover of " || $relation-map?source),
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri-inverse, $relation-map?source || " has lover " || $relation-map?target)
                )

        (: parent_of, child_of :)
        case "parent_of" return
            let $relation-type-uri-1 := $drdf:relationtypebaseuri || "is_parent_of"
            let $relation-type-uri-inverse-1 := $drdf:relationtypebaseuri || "has_parent"
            let $relation-type-uri-2 := $drdf:relationtypebaseuri || "is_child_of"
            let $relation-type-uri-inverse-2 := $drdf:relationtypebaseuri || "has_child"
            return
                (
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri-1, $relation-map?source || " is parent of " || $relation-map?target) ,
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri-inverse-1, $relation-map?target || " has parent " || $relation-map?source),
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri-2, $relation-map?target || " is child of " || $relation-map?source),
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri-inverse-2, $relation-map?source || " has child " || $relation-map?target)
                )


        (: associated_with :)
        case "associated_with" return
            let $relation-type-uri := $drdf:relationtypebaseuri || "is_associated_with"
            return
                (
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri, $relation-map?source || " is associated with " || $relation-map?target) ,
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri, $relation-map?target || " is associated with " || $relation-map?source)
                )

        (: related to :)
        case "related_with" return
             let $relation-type-uri := $drdf:relationtypebaseuri || "is_related_with"
             return
                 (
                local:relation-to-rdf($source-uri, $target-uri, $relation-type-uri, $relation-map?source || " is related with " || $relation-map?target) ,
                local:relation-to-rdf($target-uri, $source-uri, $relation-type-uri, $relation-map?target || " is related with " || $relation-map?source)
                )

        default return ()

    return $relations
};

(:~ Helper function to generate a relation in rdf:)
declare function local:relation-to-rdf($source-uri as xs:string, $target-uri as xs:string, $relation-type-uri as xs:string, $relationLabel as xs:string) {

    let $relation-uri := $drdf:relationbaseuri || util:hash((concat($source-uri,"+",$target-uri,"+",$relation-type-uri)) ,"md5")
    return
        (
    <rdf:Description rdf:about="{$relation-uri}">
        <rdf:type rdf:resource="{$drdf:dracon}relation"/>
        <dracon:has_relation_type rdf:resource="{$relation-type-uri}"/>
        <rdfs:label>{$relationLabel}</rdfs:label>
        <crm:P01_has_domain rdf:resource="{$source-uri}"/>
        <crm:P02_has_range rdf:resource="{$target-uri}"/>
    </rdf:Description> ,
    <rdf:Description rdf:about="{$source-uri}">
        <crm:P01i_is_domain_of rdf:resource="{$relation-uri}"/>
    </rdf:Description> ,
    <rdf:Description rdf:about="{$target-uri}">
        <crm:P02i_is_range_of rdf:resource="{$relation-uri}"/>
    </rdf:Description>
        )
};


(:~
 : Add genre information in RDF based on tei:textClass of a play
 :
 : @param $textClass textClass element from the play instance
 : @param $play-uri URI of the play
 : :)
declare function drdf:textClass-genre-to-rdf($textClass as element(tei:textClass) , $play-uri as xs:string ) as element()* {
    (: see function dutil:get-text-classes($tei as node()) as xs:string* {
  for $id in $tei//tei:textClass
    /tei:classCode[@scheme="http://www.wikidata.org/entity/"]/string()
  where map:contains($config:wd-text-classes, $id)
  return $config:wd-text-classes($id)
}; :)

    (: iterate over classcodes and take only the one's that are valid genre class codes as defined in $config:wd-text-classes :)

    for $textClass-id in $textClass/tei:classCode[@scheme="http://www.wikidata.org/entity/"]/string()
        where map:contains($config:wd-text-classes, $textClass-id)
        let $genre-label-string := $config:wd-text-classes($textClass-id)
        let $genre-type-uri := $drdf:genretypebaseuri || lower-case($genre-label-string)

        let $type-creation-uri := $drdf:activitybaseuri || "type_creation/" || $textClass-id
        let $type-assignment-uri := $drdf:activitybaseuri || "classification/" || util:hash((concat($genre-type-uri,"+",$play-uri)) ,"md5")

        let $type-creation-rdf :=
            (
            <rdf:Description rdf:about="{$type-creation-uri}">
                <rdf:type rdf:resource="{$drdf:crm}E83_Type_Creation"/>
                <rdfs:label>Creation of Genre Type '{$genre-label-string}' based on Wikidata-Entity '{$textClass-id}'</rdfs:label>
                <crm:P136_was_based_on rdf:resource="{$drdf:wd}{$textClass-id}"/>
                <crm:P135_created_type rdf:resource="{$genre-type-uri}"/>
            </rdf:Description>  ,
            <rdf:Description rdf:about="{$drdf:wd}{$textClass-id}">
                <crm:P136i_supported_type_creation rdf:resource="{$type-creation-uri}"/>
            </rdf:Description>
            )

        let $genre-type-rdf :=
            <rdf:Description rdf:about="{$genre-type-uri}">
                <rdf:type rdf:resource="{$drdf:crm}E55_Type"/>
                <crm:P2_has_type rdf:resource="{$drdf:typebaseuri}genre"/>
                <rdfs:label>{$genre-label-string} [Genre]</rdfs:label>
                <crm:P135i_was_created_by rdf:resource="{$type-creation-uri}"/>
                <crm:P42i_was_assigned_by rdf:resource="{$type-assignment-uri}"/>
            </rdf:Description>


        let $type-assignment-rdf :=
            (
            <rdf:Description rdf:about="{$type-assignment-uri}">
                <rdf:type rdf:resource="{$drdf:crm}E17_Type_Assignment"/>
                <rdfs:label>Assigning of Genre Type '{$genre-label-string}' to Play '{$play-uri}'</rdfs:label>
                <crm:P2_has_type rdf:resource="{$drdf:typebaseuri}classification/genre"/>
                <crm:P41_classified rdf:resource="{$play-uri}"/>
                <crm:P42_assigned rdf:resource="{$genre-type-uri}"/>
            </rdf:Description> ,
            <rdf:Description rdf:about="{$play-uri}">
                <crm:P41i_was_classified_by rdf:resource="{$type-assignment-uri}"/>
            </rdf:Description>

            )

        return
            (
             $genre-type-rdf ,
             $type-creation-rdf ,
             $type-assignment-rdf
            )

};

(:~
 : Generates crm:E42_Identifier and connect it to an crm:E1_Entity
 :
 : @param $id-uri URI of the identifier
 : @param $id-type-part part that will be added to the E55 Type after type/id/, e.g. type/id/wikidata
 : @param $label text that will be added to rdfs:label of the identifier
 : @param $identifies-uri URI of the Entity that will be identified by the identifier
 : @param $value value of the identifier
 : :)
declare function drdf:cidoc-identifier($id-uri as xs:string, $id-type-part as xs:string, $label as xs:string, $identifies-uri as xs:string, $value as xs:string)
as element()* {
    (
        <rdf:Description rdf:about="{$id-uri}">
            <rdf:type rdf:resource="{$drdf:crm}E42_Identifier"/>
            <crm:P2_has_type rdf:resource="{$drdf:typebaseuri}id/{$id-type-part}"/>
            <rdfs:label>{$label}</rdfs:label>
            <crm:P1i_identifies rdf:resource="{$identifies-uri}"/>
            <rdf:value>{$value}</rdf:value>
        </rdf:Description>,
        <rdf:Description rdf:about="{$identifies-uri}">
            <crm:P1_is_identified_by rdf:resource="{$id-uri}"/>
        </rdf:Description>
    )
};

(:~
 : Create an RDF representation of first performance of a play.
 :
 : @param $play-uri URI of the play
 : @param $label text, that will be put to rdfs:label
 : @param $yearPremiered value of year premiered as extracted by dutil-function
 : @param $ts-label text, that will be put to rdfs:label of the corresponding time-span
 :)
declare function drdf:frbroo-performance($play-uri as xs:string, $label as xs:string, $yearPremiered as xs:string, $ts-label as xs:string) {
    let $performance-uri := $play-uri || "/performance/" || "premiere"
    let $performance-type-uri := $drdf:typebaseuri || "performance" || "/premiere"
    let $work-uri := $play-uri || "/work" (: URI of the F1 !!:)
    let $timespan-uri := $performance-uri || "/ts"

    let $performance-rdf :=
        <rdf:Description rdf:about="{$performance-uri}">
            <rdf:type rdf:resource="{$drdf:frbroo}F31_Performance"/>
            <rdfs:label>{$label}</rdfs:label>
            <crm:P2_has_type rdf:resource="{$performance-type-uri}"/>
            <frbroo:R66_included_performed_version_of rdf:resource="{$work-uri}"/>
            <crm:P4_has_time-span rdf:resource="{$timespan-uri}"/>
        </rdf:Description>

    let $work-links-back :=
        <rdf:Description rdf:about="{$work-uri}">
            <frbroo:R66i_had_a_performed_version_through rdf:resource="{$performance-uri}"/>
        </rdf:Description>

    let $ts-type-uri := $drdf:typebaseuri || "date" || "/premiere" (: Premierendatum:)

    (: Premierendatum :)
    let $ts-rdf :=
        <rdf:Description rdf:about="{$timespan-uri}">
        <rdf:type rdf:resource="{$drdf:crm}E52_Time-Span"/>
        <crm:P3_has_note>dated: {$yearPremiered}</crm:P3_has_note>
        <crm:P2_has_type rdf:resource="{$ts-type-uri}"/>
        <rdfs:label>{$ts-label}</rdfs:label>
        <crm:P4i_is_time-span_of rdf:resource="{$performance-uri}"/>
    </rdf:Description>

    (: data on the year must be generated at some other point! :)
    let $year-rdf := drdf:generate-time-span-year($yearPremiered, $timespan-uri)


    (: can be connected to F1 Work / or Expression (which is risky, because we don't know, which version was performed; and if that's the version that we are using) :)
    (: R66 included performed version of (had a performed version through) :)

    return
       ( $performance-rdf ,
         $work-links-back ,
         $ts-rdf,
         $year-rdf
       )
};


(:~
 : Create an RDF representation of the F1 Work of a play.
 :
 : @param $play-uri URI of the play
 : @param $label text, that will be put to rdfs:label
 : @param $yearWritten value of year written as extracted by dutil-function
 : @param $ts-label text, that will be put to rdfs:label of the corresponding time-span
 :)
declare function drdf:frbroo-entites($play-uri as xs:string) {
    let $work-uri := $play-uri || "/work"

    let $work-rdf :=
        <rdf:Description rdf:about="{$work-uri}">
            <rdf:type rdf:resource="{$drdf:frbroo}F14_Individual_Work"/>
        </rdf:Description>

    return
        ( $work-rdf)

};

(:
 : Generates time-span of a calendar year and connects it to time-spans that fall within this year
 :
 : @param $year-value, e.g. 1905
 : @param $uris sequence of uris that fall within this year
 :
 :  :)
declare function drdf:generate-time-span-year($year-value as xs:string, $uris as xs:string*)
as element()* {
    let $year-type-uri := $drdf:typebaseuri || "date" || "/year"
    let $year-uri :=
        if (matches($year-value, "^\d+$")) then
            $drdf:datebaseuri || $year-value
        else ""

    return
        if ($year-uri != "") then
            (
            <rdf:Description rdf:about="{$year-uri}">
                <rdf:type rdf:resource="{$drdf:crm}E52_Time-Span"/>
                <rdfs:label>{$year-value} [Year]</rdfs:label>
                <crm:P2_has_type rdf:resource="{$year-type-uri}"/>
                {
                    for $uri in $uris return
                        <crm:P86i_contains rdf:resource="{$uri}"/>
                }
            </rdf:Description> ,
            for $uri in $uris return
                <rdf:Description rdf:about="{$uri}">
                    <crm:P86_falls_within rdf:resource="{$year-uri}"/>
                </rdf:Description>
            )
    else ()
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

    (: written, print and premiere years are actually string-values, 1919/1920...; removed the explicit datatype --> will be untyped literal in RDF Serialization :)

    let $writtenYear :=
        if ( map:contains($play-info, "yearWritten") ) then
            if ( $play-info?yearWritten ) then
                <dracon:writtenYear>
                    {$play-info?yearWritten}
                </dracon:writtenYear>
            else ()
        else ()

    let $printYear :=
        if ( map:contains($play-info, "yearPrinted") ) then
            if ( $play-info?yearPrinted ) then
                <dracon:printYear>
                    {$play-info?yearPrinted}
                </dracon:printYear>
            else ()
        else ()


    let $premiereYear :=
        if ( map:contains($play-info, "yearPremiered") ) then
                if ( $play-info?yearPremiered ) then
                <dracon:premiereYear>
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
    let $allInIndex :=
        if ( map:contains($play-info, "allInIndex") ) then
            <dracon:allInIndex rdf:datatype="http://www.w3.org/2001/XMLSchema#decimal">
                {$play-info?allInIndex}
            </dracon:allInIndex>
        else ()

    (: "allInSegment" should point to a segment :)
    let $allInSegment :=
        if ( map:contains($play-info, "allInSegment") ) then
            let $allInSegment-uri := $play-uri || "/segment/" || xs:string($play-info?allInSegment)
            return
                <dracon:allInSegment rdf:resource="{$allInSegment-uri}"/>
        else
            ()


    (: wikidata-id of the play: "wikidataId": "Q51370104", :)
    let $sameAs-wikidata :=
        if ( map:contains($play-info, "wikidataId") ) then
            <owl:sameAs rdf:resource="{$drdf:wd || $play-info?wikidataId}"/>
        else ()

    (: should add external identifiers via crm:identified by... :)
    let $wd-identifier-cidoc :=
        if ( map:contains($play-info, "wikidataId") ) then
            let $wd-identifier-uri := $play-uri || "/id/wikidata"
            let $wd-identifier-label := "Wikidata Identifier of play '" || $defaultTitleString ||"'"
            return
                drdf:cidoc-identifier($wd-identifier-uri, "wikidata", $wd-identifier-label , $play-uri, $play-info?wikidataId)
        else ()

    (: dracor-identifiers id and playname cidoc style :)
    let $playname-id-uri := $play-uri || "/id/playname"
    let $playname-id-label := "DraCor Identifier 'playname' of play '" || $defaultTitleString || "'"
    let $playname-id-rdf := drdf:cidoc-identifier($playname-id-uri, "playname", $playname-id-label , $play-uri, $playname)

    (: dracor-id :)
    let $dracor-id-uri := $play-uri || "/id/dracor"
    let $dracor-id-label := "DraCor Identifier of play '" || $defaultTitleString || "'"
    let $dracor-id-rdf := drdf:cidoc-identifier($dracor-id-uri, "dracor", $dracor-id-label , $play-uri, $play-info?id)



    (: "originalSource" :)
    (: maybe use dc:source :)
    let $dc-source :=
        if ( map:contains($play-info, "originalSource") ) then
            <dc:source>{$play-info?originalSource}</dc:source>
        else ()

    (: todo digital source! :)

  (: some metrics are only in dutil:dutil:get-corpus-meta-data; which could be moved to separate dutil function  - see https://github.com/dracor-org/dracor-api/issues/152 :)

  (:
   "numOfSegments": count(dutil:get-segments($tei)),
    "numOfActs": count($tei//tei:div[@type="act"]), --> implemented
    "numOfSpeakers": $num-speakers, --> implemented
    "numOfSpeakersMale": $num-male,
    "numOfSpeakersFemale": $num-female,
    "numOfSpeakersUnknown": $num-unknown,
    "numOfPersonGroups": $num-groups,
    "numOfP": $num-p,
    "numOfL": $num-l,
  :)

  (: in dutil:get-corpus-meta-data: "numOfActs": count($tei//tei:div[@type="act"]), :)
  let $numOfActs :=
        if ( $play//tei:div[@type eq "act"] ) then
        <dracon:numOfActs rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
            {count($play//tei:div[@type eq "act"])}
        </dracon:numOfActs>
        else ()

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

    (: numOfSpeakers :)
    (: let $num-speakers := count(dutil:distinct-speakers($tei)) :)
    (: same as networkSize? :)
    (: could count cast :)
    let $num-speakers := count(dutil:distinct-speakers($play))
    let $numOfSpeakers :=
        <dracon:numOfSpeakers rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {$num-speakers}
        </dracon:numOfSpeakers>

    (: gender of speakers :)
    (: copied code from dutil:get-corpus-meta-data :)
    let $cast-tei := $play//tei:particDesc/tei:listPerson/(tei:person|tei:personGrp)
    let $num-male := count($cast-tei[@sex="MALE"])
    let $num-female := count($cast-tei[@sex="FEMALE"])
    let $num-unknown := count($cast-tei[@sex="UNKNOWN"])
    let $num-groups := count($cast-tei[name()="personGrp"])

    let $numOfSpeakersMale :=
        <dracon:numOfSpeakersMale rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {$num-male}
        </dracon:numOfSpeakersMale>

    let $numOfSpeakersFemale :=
        <dracon:numOfSpeakersFemale rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {$num-female}
        </dracon:numOfSpeakersFemale>

    let $numOfSpeakersUnknown :=
        <dracon:numOfSpeakersUnknown rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {$num-unknown}
        </dracon:numOfSpeakersUnknown>

    let $numOfSpeakerGroups :=
        <dracon:numOfSpeakerGroups rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {$num-groups}
        </dracon:numOfSpeakerGroups>

    (: only in dutil:get-corpus-meta-data :)
    (:     "numOfP": $num-p,
    "numOfL": $num-l, :)
    let $num-p := count($play//tei:body//tei:sp//tei:p)
    let $num-l := count($play//tei:body//tei:sp//tei:l)

    let $numOfParagraphs :=
        <dracon:numOfParagraphs rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
            {$num-p}
        </dracon:numOfParagraphs>

    let $numOfLines :=
        <dracon:numOfLines rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
            {$num-l}
        </dracon:numOfLines>


    (: segments :)
    let $segments := drdf:segments-to-rdf($play-info?segments, $play-uri, $play-info?title )

    (: cast :)
    let $cast := drdf:characters-to-rdf($corpusname, $playname, $play-info?title, $play-uri, false() , false()) (: use $play-info?title for playtitle, do not include metrics, do not wrap :)

    (: (social)relations of characters of a play :)
    let $relations := drdf:relations-to-rdf($play-info?relations, $play-uri )

    (: genre :)
    (: in play-info: "genre": "Tragedy", :)
    (: functionality somehow in of dutil:get-corpus-meta-data, but modelling will be more complex! :)
    let $tei-textClass :=  $play//tei:textClass
    let $genre-rdf := if ($tei-textClass//tei:classCode) then drdf:textClass-genre-to-rdf($tei-textClass, $play-uri) else ()

    (: (first) performance :)
    let $rdf-first-performance :=
        if ( map:contains($play-info, "yearPremiered") ) then
                let $first-performance-label := "Premiere of " || $default-rdfs-label-string
                let $first-performance-ts-label := "Premiere of " || $default-rdfs-label-string || " [Time-span]"
                return drdf:frbroo-performance($play-uri, $first-performance-label, $play-info?yearPremiered, $first-performance-ts-label)
        else ()

    (: frbroo:F1 Work :)
    (: must be linked to performace and play-entity :)
    let $work-rdf := drdf:frbroo-entites($play-uri)

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
      {$numOfActs}
      {$numOfLines}
      {$numOfParagraphs}
      {$numOfSpeakers}
      {$numOfSpeakersMale}
      {$numOfSpeakersFemale}
      {$numOfSpeakersUnknown}
      {$numOfSpeakerGroups}
      {$allInIndex}
      {$allInSegment}
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
    {$cast}
    {$segments}
    {$relations}
    {$genre-rdf}
    {$wd-identifier-cidoc}
    {$playname-id-rdf}
    {$dracor-id-rdf}
    {$rdf-first-performance}
    {$work-rdf}
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

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

(:~
 : Create an RDF representation of a play.
 :
 : @param $play TEI element
 : @author Ingo Börner
 : @author Carsten Milling
 :)
declare function drdf:play-to-rdf ($play as element(tei:TEI))
as element(rdf:RDF) {
  (: store data for triples in variables :)
  (: http://dracor.org/ontology#in_corpus :)
  let $paths := dutil:filepaths($play/base-uri())
  let $corpusname := $paths?corpusname
  let $playname := $paths?playname
  let $metricspath := $paths?files?metrics
  let $metrics := doc($metricspath)

  (: should get the id of the play <idno type='dracor' :)
  let $play-id := dutil:get-dracor-id($play)

  (: maybe /id/{id} could be used in the future :)
  let $play-uri :=
    if ($play-id != "")
    then "https://dracor.org/entity/" || $play-id
    else "https://dracor.org/" || $corpusname || "/" || $playname

  (:
   : get metadata of play to generate rdfs:label, dc:creator, dc:title ,...
   :)

  (: handle multilingual titles "main"/"sub"... :)
  (: maybe this part could be or is handled by a separate function? :)
  let $titles := array {
    for $lang in distinct-values(
      $play//tei:titleStmt//tei:title/@xml:lang/string()
    ) return
      map {
        "lang": $lang,
        "main": normalize-space(
          $play//tei:titleStmt//tei:title[@type = "main"][@xml:lang = $lang]
          /string()
        ),
        "sub": normalize-space(
          $play//tei:titleStmt//tei:title[@type = "sub"][@xml:lang = $lang]
          /string()
        )
      }
  }

  (: handle multilingual author-names... :)
  let $author-names := array {
    if ($play//tei:titleStmt//tei:author/@xml:lang)
    then
      for $lang in distinct-values(
        $play//tei:titleStmt//tei:author/@xml:lang/string()
      ) return
        map {
          "lang": $lang,
          "name": distinct-values(
            $play//tei:titleStmt//tei:author[@xml:lang=$lang]/string()
          )
        }
    else
      map {
        "lang": "",
        "name": distinct-values($play//tei:titleStmt//tei:author/string())
      }
  }

  (: handle multiple key-values, decide if gnd or wikidata :)
  let $author-idnos := array {
    (: if there would be multiple values in key, tokenize them :)
    for $author in $play//tei:titleStmt//tei:author[@key]
    let $key := $author/@key/string()
    return
      map {
        "label": $author/text(),
        "id-type":
          if (matches($key, "(w|W)ikidata:Q[0-9]*?")) then "wikidata"
          else if (matches($key, "pnd:[0-9X]*?")) then "pnd"
          else (),
        "id-value": replace($key, ".*?:([0-9X]*?)", "$1" ),
        "uri":
          if (matches($key, "(w|W)ikidata:Q[0-9]*?"))
          then "http://www.wikidata.org/entity/"
            || replace($key, ".*?:([0-9X]*?)", "$1")
          else if (matches($key, "pnd:[0-9X]*?"))
          then "http://d-nb.info/gnd/"
            || replace($key, ".*?:([0-9X]*?)", "$1")
          else ()
      }


  }

  (: generate blank nodes for authors :)
  let $author-nodes :=
    (: maybe check, if there are distinct authors.. how could i detect this
    case? :)
    <dracon:has_author>
      <rdf:Description>
      {
        if (count($author-names) > 1) then
          for $author-lang in $author-names
          return
            <rdfs:label xml:lang="{$author-lang?lang}">
              {$author-lang?name}
            </rdfs:label>
        else
          <rdfs:label>{$author-names?1?name}</rdfs:label>
      }
      {
        for $author-idno in $author-idnos?*
        return <owl:sameAs rdf:resource="{$author-idno?uri}"/>
      }
      </rdf:Description>
    </dracon:has_author>

  let $collection-uri := "https://dracor.org/" || $corpusname

  (: construct rdfs:labels – Author : Title. Subtitle.
   : If there is no @xml:lang on tei:author, skip author-name; but include
   : name in the label in the language of the play :)
  let $rdfs-labels := for $lang in $titles?*?lang return
    <rdfs:label xml:lang="{$lang}">
      {
        if ($author-names?*[?lang = $lang])
        then $author-names?*[?lang = $lang]?name
        else if (
          not($play//tei:titleStmt//tei:author/@xml:lang)
          and $play/@xml:lang = $lang
        )
        then $author-names?1?name || ": "
        else ""
      }
      {
        if ($author-names?*[?lang = $lang] and $titles?*[?lang = $lang]?main)
        then ": "
        else ""
      }
      {
        if ($titles?*[?lang = $lang]?main)
        then $titles?*[?lang = $lang]?main
        else ""
      }
      {
        if ($titles?*[?lang = $lang]?sub)
        then ". " || $titles?*[?lang = $lang]?sub
        else "."
      }
    </rdfs:label>

  (: construct dc:creator for each language, if there xml:lang tags on
  tei:author :)
  let $dc-creator :=
    if (count($author-names) > 1) then
      for $creator-lang in $author-names return
        <dc:creator xml:lang="{$creator-lang?lang}">
          {$creator-lang?name}
        </dc:creator>
    else
      <dc:creator>{$author-names?1?name}</dc:creator>

  (: construct dc:title tags for each language :)
  let $dc-titles :=
    for $lang in $titles?*?lang return
      if ($titles?*[?lang = $lang]?main or $titles?*[?lang = $lang]?sub)
      then
        <dc:title xml:lang="{$lang}">
          {
            if ($titles?*[?lang = $lang]?main)
            then $titles?*[?lang = $lang]?main
            else ""
          }
          {
            if ($titles?*[?lang = $lang]?sub)
            then ". " || $titles?*[?lang = $lang]?sub
            else "."
          }
        </dc:title>
      else ()

  let $in_corpus := <dracon:in_corpus rdf:resource="{$collection-uri}"/>

  let $wikidata-id := dutil:get-play-wikidata-id($play)
  let $play-external-id := if ($wikidata-id)
    then <owl:sameAs rdf:resource="http://www.wikidata.org/entity/{$wikidata-id}"/>
    else ()

  (: CIDOC-Stuff :)
  let $creation-uri := $play-uri || "/creation"
  let $created-by :=  <crm:P94i_was_created_by rdf:resource="{$creation-uri}"/>

  let $creation-activity :=
    <rdf:Description rdf:about="{$creation-uri}">
      <rdf:type rdf:resource="http://www.cidoc-crm.org/cidoc-crm/E65_Creation"/>
      <crm:P94_has_created rdf:resource="{$play-uri}"/>
      {
        for $author-idno in $author-idnos?*
        return
          <crm:P14_carried_out_by rdf:resource="{$author-idno?uri}"/>
      }
    </rdf:Description>

    let $dracor-link :=
      <rdfs:seeAlso rdf:resource="https://dracor.org/{$corpusname}/{$playname}"/>

    (: metrics :)

    let $averageClustering :=
      if ($metrics/metrics/network/averageClustering/text() != "")
      then
        <dracon:averageClustering>
          {$metrics/metrics/network/averageClustering/text()}
        </dracon:averageClustering>
      else ()

    let $averagePathLength :=
      if ( $metrics/metrics/network/averagePathLength/text() != "" )
      then
        <dracon:averagePathLength>
          {$metrics/metrics/network/averagePathLength/text()}
        </dracon:averagePathLength>
      else ()

    let $averageDegree :=
      if ( $metrics/metrics/network/averageDegree/text() != "" )
      then
        <dracon:averageDegree>
          {$metrics/metrics/network/averageDegree/text()}
        </dracon:averageDegree>
      else ()

    let $density :=
      if ( $metrics/metrics/network/density/text() != "" )
      then
        <dracon:density>
          {$metrics/metrics/network/density/text()}
        </dracon:density>
      else ()

    let $diameter :=
      if ( $metrics/metrics/network/diameter/text() != "" )
      then
        <dracon:diameter>
          {$metrics/metrics/network/diameter/text()}
        </dracon:diameter>
      else ()

    let $maxDegree :=
      if ( $metrics/metrics/network/maxDegree/text() != "" )
      then
        <dracon:maxDegree>
          {$metrics/metrics/network/maxDegree/text()}
        </dracon:maxDegree>
      else ()

    let $maxDegreeIds :=
      for $character in tokenize($metrics/metrics/network/maxDegreeIds/text(),' ')
      let $character-uri := $play-uri || '/character/' || $character
      return <dracon:maxDegreeCharacter rdf:resource="{$character-uri}"/>

    let $numOfActs :=
      if ( count($play//tei:div[@type="act"]) > 0 )
      then
        <dracon:numOfActs rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {count($play//tei:div[@type="act"])}
        </dracon:numOfActs>
      else ()

    let $numOfSegments :=
      <dracon:numOfSegments rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
        {count(dutil:get-segments($play))}
      </dracon:numOfSegments>

    let $numOfSpeakers :=
      if (count($play//tei:particDesc/tei:listPerson/(tei:person|tei:personGrp)) > 0)
      then
        <dracon:numOfSpeakers rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
          {count($play//tei:particDesc/tei:listPerson/(tei:person|tei:personGrp))}
        </dracon:numOfSpeakers>
      else ()

    (: Dates :)
    let $years := dutil:get-years-iso($play)
    let $yn := dutil:get-normalized-year($play)

    let $normalisedYear :=
      if ($yn)
      then
        <dracon:normalisedYear rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
          {$yn}
        </dracon:normalisedYear>
      else ()

    let $yearPremiered :=
      if (matches($years?premiere, "^-?[0-9]{4}$"))
      then
        <dracon:yearPremiered rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
          {$years?premiere}
        </dracon:yearPremiered>
      else ()

    let $yearPrinted :=
      if (matches($years?print, "^-?[0-9]{4}$"))
      then
        <dracon:yearPrinted rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
          {$years?print}
        </dracon:yearPrinted>
      else ()

    let $yearWritten :=
      if (matches($years?written, "^-?[0-9]{4}$"))
      then
        <dracon:yearWritten rdf:datatype="http://www.w3.org/2001/XMLSchema#gYear">
          {$years?written}
        </dracon:yearWritten>
      else ()

    (: characters :)
    let $characters :=
      $play//tei:particDesc/tei:listPerson/tei:person

    let $charactersindrama :=
      for $character in $characters
        let $character-uri :=
          $play-uri || "/character/" || $character/@xml:id/string()
      return
        <schema:character rdf:resource="{$character-uri}"/>

    let $characterDescriptions :=
      for $character in $characters
      let $character-uri := $play-uri || "/character/" || $character/@xml:id/string()
      return
        <rdf:Description rdf:about="{$character-uri}">
          <rdf:type rdf:resource="http://iflastandards.info/ns/fr/frbr/frbroo/F38_Character"/>
            {
              for $persName in $character/tei:persName return
                <rdfs:label
                  xml:lang="{
                    if ($persName/@xml:lang)
                    then $persName/@xml:lang
                    else $play/@xml:lang}"
                >
                  {$persName/string()}
                </rdfs:label>
              }
              {
                if ($character/@ana) then
                  if (matches($character/@ana/string(), 'https://wikidata.org/wiki/'))
                  then
                    let $wd :=
                      substring-after($character/@ana/string(),'https://www.wikidata.org/wiki/')
                      return
                        <owl:sameAs rdf:resource="http://www.wikidata.org/entity/{$wd}"/>
                  else if ( matches($character/@ana/string(), 'https://www.wikidata.org/entity/') )
                  then
                    let $wd := substring-after($character/@ana/string(),'https://www.wikidata.org/entity/')
                    return
                      <owl:sameAs rdf:resource="http://www.wikidata.org/entity/{$wd}"/>
                  else if ( matches($character/@ana/string(), 'http://www.wikidata.org/entity/') )
                  then <owl:sameAs rdf:resource="{$character/@ana/string()}"/>
                  else ()
                else ()
              }
          </rdf:Description>

  let $inner :=
    <rdf:Description rdf:about="{$play-uri}">
      <rdf:type rdf:resource="http://www.cidoc-crm.org/cidoc-crm/E33_Linguistic_Object"/>
      <rdf:type rdf:resource="http://dracor.org/ontology#play"/>
      {$rdfs-labels}
      {$dc-creator}
      {$dc-titles}
      {$author-nodes}
      {$created-by}
      {$in_corpus}
      {$play-external-id}
      {$dracor-link}
      {$averageClustering}
      {$averageDegree}
      {$averagePathLength}
      {$density}
      {$diameter}
      {$maxDegree}
      {$maxDegreeIds}
      {$normalisedYear}
      {$numOfActs}
      {$numOfSegments}
      {$numOfSpeakers}
      {$yearPremiered}
      {$yearPrinted}
      {$yearWritten}
      {$charactersindrama}
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
      {$creation-activity}
      {$characterDescriptions}
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
  let $log := util:log-system-out(
    "Clearing fuseki graph <" || $graph || "> at " || $url
  )
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

  let $response := try {
     hc:send-request($request, $url)
  } catch * {
    util:log-system-out($err:description)
  }

  return if ($response/@status = "204") then (
    true()
  ) else (
    util:log-system-out(
      "Failed to clear graph! " || (
        if ($response/message) then $response/message else ""
      )
    ),
    false()
  )
};

(:~
 : Send RDF data to Fuseki
 : https://github.com/dracor-org/dracor-api/issues/77
 :)
declare function drdf:fuseki($uri as xs:anyURI) {
  let $corpus := tokenize($uri, "/")[position() = last() - 1]
  let $url := $config:fuseki-server || "data" || "?graph=" || encode-for-uri("http://dracor.org/" || $corpus)
  let $rdf := doc($uri)

  return (
    util:log-system-out(
      "Posting " || $uri || " to " || $url
    ),
    if (not($rdf)) then (
      util:log-system-out("Cannot find " || $uri),
      false()
    ) else (
      let $request :=
        <hc:request method="post" href="{ $url }">
          <hc:body media-type="application/rdf+xml">{ $rdf }</hc:body>
        </hc:request>

      let $response := try {
        hc:send-request($request)
      } catch * {
        util:log-system-out($err:description)
      }

      return if ($response) then
        switch (string($response[1]/@status))
          case "200" return true()
          case "201" return true()
          default return (
            util:log-system-out("response header from fuseki: " || $response[1]),
            util:log-system-out("response body from fuseki: " || $response[2])
          )
      else false()
    )
  )
};

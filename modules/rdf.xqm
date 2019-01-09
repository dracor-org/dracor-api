xquery version "3.1";

(:~
 : DraCor RDF module
 :)
module namespace drdf = "http://dracor.org/ns/exist/rdf";

import module namespace config = "http://dracor.org/ns/exist/config"
  at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: Namespaces for Linked Open Data :)
declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";
declare namespace rdfs="http://www.w3.org/2000/01/rdf-schema#" ;
declare namespace owl="http://www.w3.org/2002/07/owl#";
declare namespace dc="http://purl.org/dc/elements/1.1/";
declare namespace dracon="http://dracor.org/ontology#";

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

  (: should get the id of the play <idno type='dracor' :)
  let $play-id := $play//tei:publicationStmt//tei:idno[@type="dracor"]/text()

  (: maybe /id/{id} could be used in the future :)
  let $play-uri :=
    if ($play-id != "")
    then "https://dracor.org/id/" || $play-id
    else "https://dracor.org/" || $corpusname || "/" || $playname

  (:
   : get metadata of play to generate rdfs:label, dc:creator, dc:title ,...
   :)

  (: handle multilingual titles "main"/"sub"... :)
  (: maybe this part could be or is handled by a seperate function? :)
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

  let $wikidata-play-uri := "http://www.wikidata.org/entity/" ||
    $play//tei:publicationStmt//tei:idno[@type="wikidata"]/text()

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
  let $play-external-id := <owl:sameAs rdf:resource="{$wikidata-play-uri}"/>

  let $inner :=
    <rdf:Description rdf:about="{$play-uri}">
      <owl:sameAs rdf:resource="{$wikidata-play-uri}"/>
      {$rdfs-labels}
      {$dc-creator}
      {$dc-titles}
      {$author-nodes}
      {$in_corpus}
      {$play-external-id}
    </rdf:Description>

  return
    <rdf:RDF
      xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      xmlns:owl="http://www.w3.org/2002/07/owl#"
      xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
      xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:dracon="http://dracor.org/ontology#"
    >
      {$inner}
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
    xmldb:store($collection, $resource, $rdf)
  )
};

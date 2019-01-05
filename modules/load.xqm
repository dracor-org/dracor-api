xquery version "3.1";

(:~
 : Module providing function to load files from zip archives.
 :)
module namespace load = "http://dracor.org/ns/exist/load";

import module namespace config="http://dracor.org/ns/exist/config" at "config.xqm";
declare namespace compression = "http://exist-db.org/xquery/compression";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: Namespaces for Linked Open Data :)
declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";
declare namespace rdfs="http://www.w3.org/2000/01/rdf-schema#" ;
declare namespace owl="http://www.w3.org/2002/07/owl#";
declare namespace dc="http://purl.org/dc/elements/1.1/";
declare namespace dracon="http://dracor.org/ontology#";
(: /Namespaces for Linked Open Data :)




declare function local:entry-data(
  $path as xs:anyURI, $type as xs:string, $data as item()?, $param as item()*
) as item()? {
  if($data) then
    let $collection := $param[1]
    let $name := tokenize($path, '/')[last()]
    let $res := xmldb:store($collection, $name, $data)
    return $res
  else
    ()
};

declare function local:entry-filter(
  $path as xs:anyURI, $type as xs:string, $param as item()*
) as xs:boolean {
  (: filter paths using only files in the "tei" subdirectory  :)
  if ($type eq "resource" and contains($path, "/tei/"))
  then
    true()
  else
    false()
};

(:~
 : Load corpus from ZIP archive
 :
 : @param $name The name of the corpus
:)
declare function load:load-corpus($name as xs:string) {
  let $corpus := $config:corpora//corpus[name = $name]
  return if ($corpus) then
    <loaded>
    {
      for $doc in load:load-archive($corpus/name, $corpus/archive)
      return <doc>{$doc}</doc>
    }
    </loaded>
  else
    ()
};

(:~
 : Load XML files from ZIP archive
 :
 : @param $name The name of the sub collection to create
 : @param $archive-url The URL of a ZIP archive containing XML files
:)
declare function load:load-archive($name as xs:string, $archive-url as xs:string) {
  let $collection := xmldb:create-collection($config:data-root, $name)
  (: returns empty sequence when collection already available. so we set again: :)
  let $collection := $config:data-root || "/" || $name
  let $removals := for $res in xmldb:get-child-resources($collection)
                   return xmldb:remove($collection, $res)
  let $gitRepo := httpclient:get($archive-url, false(), ())
  let $zip := xs:base64Binary(
    $gitRepo//httpclient:body[@mimetype="application/zip"][@type="binary"]
    [@encoding="Base64Encoded"]/string(.)
  )

  return (
    compression:unzip(
      $zip,
      util:function(xs:QName("local:entry-filter"), 3),
      (),
      util:function(xs:QName("local:entry-data"), 4),
      ($collection)
    )
  )
};

(:~ Generates an RDF-Dump of the data; stores file in $config:rdf-root
  @author Ingo Börner
:)
declare function load:generateRDF() {
  let $rdf-collection := $config:data-root || "/rdf"

  let $plays := collection($config:data-root)//tei:TEI

  for $play in $plays


    (: store data for triples in variables :)

    (: http://dracor.org/ontology#in_corpus :)
    let $collection-id := (
      replace($play/base-uri(),$config:data-root,'') => tokenize("/")
    )[2]

    (: used for URI of play at the moment; could be used for rdfs:seeAlso web-presentation  :)
    let $play-name := ($play/base-uri() => tokenize("/"))[last()] => substring-before('.xml')

    (: should get the id of the play <idno type='dracor' :)
    let $play-id := $play//tei:publicationStmt//tei:idno[@type='dracor']/text()

    (: maybe /id/{id} could be used in the future :)
    let $play-uri :=
        if ($play-id != '') then 'https://dracor.org/id/' || $play-id
        else 'https://dracor.org/' || $collection-id || "/" || $play-name

    (: get metadata of play to generate rdfs:label, dc:creator, dc:title ,... :)

    (: handle multilungual titles "main"/"sub"... :)
    (: maybe this part could be or is handled by a seperate function? :)
    let $titles := array {
        for $lang in distinct-values($play//tei:titleStmt//tei:title/@xml:lang/string()) return
            map {
                "lang" : $lang,
                "main" : normalize-space($play//tei:titleStmt//tei:title[@type = 'main'][@xml:lang = $lang]/string()),
                "sub" : normalize-space($play//tei:titleStmt//tei:title[@type = 'sub'][@xml:lang = $lang]/string())
            }
    }

    (: handle multilingual author-names... :)
    let $author-names := array {
        if ( $play//tei:titleStmt//tei:author/@xml:lang ) then
            for $lang in distinct-values($play//tei:titleStmt//tei:author/@xml:lang/string()) return
                map {
                    "lang" : $lang,
                    "name" : distinct-values($play//tei:titleStmt//tei:author[@xml:lang=$lang]/string())
                }
        else
            map {
                "lang" : '',
                "name" : distinct-values($play//tei:titleStmt//tei:author/string())
            }
    }

    (: handle multiple key-values, decide if gnd or wikidata :)
    let $author-idnos := array {
        (: if there would be multiple values in key, tokenize them:)
        (: for $key in tokenize($play//tei:titleStmt//tei:author/@key/string(),' ')
        return :)
            for $author in $play//tei:titleStmt//tei:author[@key]
            let $key := $author/@key/string()
            return
                map {
                    "label" : $author/text(),
                    "id-type" :
                        if ( matches($key, '(w|W)ikidata:Q[0-9]*?') ) then 'wikidata'
                        else if ( matches($key, 'pnd:[0-9X]*?') ) then 'pnd'
                        else () ,
                    "id-value" : replace($key, '.*?:([0-9X]*?)', '$1' ),
                    "uri" :
                        if ( matches($key, '(w|W)ikidata:Q[0-9]*?') ) then 'http://www.wikidata.org/entity/' || replace($key, '.*?:([0-9X]*?)', '$1')
                        else if ( matches($key, 'pnd:[0-9X]*?') ) then 'http://d-nb.info/gnd/' || replace($key, '.*?:([0-9X]*?)', '$1')
                        else ()
            }


    }

    (: generate blank nodes for authors :)

    let $author-nodes :=
        (: maybe check, if there are distinct authors.. how could i detect this case? :)
        <dracon:has_author>
            <rdf:Description>
                {
                    if ( count($author-names) > 1 ) then
                        for $author-lang in $author-names return
                            <rdfs:label xml:lang="{$author-lang?lang}">{$author-lang?name}</rdfs:label>
                    else
                        <rdfs:label>{$author-names?1?name}</rdfs:label>

                }
                {
                        for $author-idno in $author-idnos?* return
                            <owl:sameAs rdf:resource="{$author-idno?uri}"/>
                }

            </rdf:Description>
        </dracon:has_author>



    let $wikidata-play-uri := "http://www.wikidata.org/entity/" ||
      $play//tei:publicationStmt//tei:idno[@type='wikidata']/text()


    (:
    let $label := (
      $play//tei:fileDesc/tei:titleStmt//tei:author/text() => string-join(' ')
    ) || ": " || (
      $play//tei:fileDesc/tei:titleStmt//tei:title/text() => string-join(' ')
    )
    :)

    let $collection-uri := "https://dracor.org/" || $collection-id


    (: construct rdfs:labels – Author : Title. Subtitle. If there is no @xml:lang on tei:author, skip author-name; but include name in the label in the language of the play :)
    let $rdfs-labels := for $lang in $titles?*?lang
        return <rdfs:label xml:lang="{$lang}">{
            if ( $author-names?*[?lang = $lang] )
            then $author-names?*[?lang = $lang]?name
            else if ( not($play//tei:titleStmt//tei:author/@xml:lang) and $play/@xml:lang = $lang ) then $author-names?1?name || ': '
            else ""

            }

            {
                if (  $author-names?*[?lang = $lang] and $titles?*[?lang = $lang]?main  ) then ": " else ""
            }
            {
                if ( $titles?*[?lang = $lang]?main ) then $titles?*[?lang = $lang]?main
                else ""
            }

            {
                if ( $titles?*[?lang = $lang]?sub ) then ". " || $titles?*[?lang = $lang]?sub
                else "."
            }

            </rdfs:label>

        (: construct dc:creator for each language, if there xml:lang tags on tei:author :)
            let $dc-creator := if ( count($author-names) > 1 ) then
                for $creator-lang in $author-names return
                    <dc:creator xml:lang="{$creator-lang?lang}">{$creator-lang?name}</dc:creator>
            else
                <dc:creator>{$author-names?1?name}</dc:creator>

        (: construct dc:title tags for each language :)
        let $dc-titles := for $lang in $titles?*?lang
        return
            if ( $titles?*[?lang = $lang]?main or $titles?*[?lang = $lang]?sub ) then

            <dc:title xml:lang="{$lang}">{
                if ( $titles?*[?lang = $lang]?main ) then $titles?*[?lang = $lang]?main
                else ""
            }

            {
                if ( $titles?*[?lang = $lang]?sub ) then ". " || $titles?*[?lang = $lang]?sub
                else "."
            }</dc:title>

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

    let $play_as_rdf :=  <rdf:RDF
      xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
      xmlns:owl="http://www.w3.org/2002/07/owl#"
      xmlns:rdfs="http://www.w3.org/2000/01/rdf-schema#"
      xmlns:dc="http://purl.org/dc/elements/1.1/"
      xmlns:dracon="http://dracor.org/ontology#"
    >
      {$inner}
    </rdf:RDF>

    return $play_as_rdf

      (: , xmldb:store($rdf-collection, $rdf-filename, $rdf-data) :)

};

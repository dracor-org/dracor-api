xquery version "3.1";

(:
 : DTS Endpoint
 : This module implements the DTS (Distributed Text Services) API specification – https://distributed-text-services.github.io/specifications/
 : developed for the DTS Hackathon https://distributed-text-services.github.io/workshops/events/2021-hackathon/ by Ingo Börner
 :)

(: ddts – DraCor-Implementation of DTS follows naming conventions, e.g. dutil :)
module namespace ddts = "http://dracor.org/ns/exist/dts";

import module namespace config = "http://dracor.org/ns/exist/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util" at "util.xqm";
import module namespace openapi = "https://lab.sub.uni-goettingen.de/restxqopenapi";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: Namespaces mentioned in the spec:  :)
declare namespace dts = "https://w3id.org/dts/api#";
declare namespace hydra = "https://www.w3.org/ns/hydra/core#";
declare namespace dc = "http://purl.org/dc/terms/";

(: Variables used in responses :)
declare variable $ddts:api-base := "https://staging.dracor.org/api"; (: change for production :)
declare variable $ddts:collections-base := "/dts/collections" ;
declare variable $ddts:documents-base := "/dts/documents" ;

declare variable $ddts:ns-dts := "https://w3id.org/dts/api#";
declare variable $ddts:ns-hydra := "https://www.w3.org/ns/hydra/core#";
declare variable $ddts:ns-dc := "http://purl.org/dc/terms/";

(: fixed parts in response, e.g. namespaces :)
declare variable $ddts:context :=
  map {
      "@vocab": $ddts:ns-hydra,
      "dc": $ddts:ns-dc,
      "dts": $ddts:ns-dts
  };


(:
 : --------------------
 : Entry Point
 : --------------------
 :
 : see https://distributed-text-services.github.io/specifications/Entry.html
 : /api/dts
 :)

(:~
 : DTS Entry Point
 :
 : Main Entry Point to the DTS API. Provides the base path for each of the 3 specified endpoints: collections, navigation and documents.
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/dts")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function ddts:entry-point() {
  map {
    "@context": "/dts/contexts/EntryPoint.jsonld",
    "@id": "/dts",
    "@type": "EntryPoint",
    "collections": "/dts/collections",
    "documents": "/dts/documents",
    "navigation" : "/dts/navigation"
  }
};


(:
 : --------------------
 : Collections Endpoint
 : --------------------
 :
 : see https://distributed-text-services.github.io/specifications/Collections-Endpoint.html
 : could be /api/dts/collections
 :)

(: add function description here! :)
declare
  %rest:GET
  %rest:path("/dts/collections")
  %rest:query-param("id", "{$id}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function ddts:collections($id) {

  (: check, if param $id is set -- request a certain collection :)
  if ( $id ) then

    (: if root-collection "corpora is explicitly requested by id = 'corpora'" :)
    if ( $id eq "corpora" ) then
        local:root-collection()
    else
        (: evaluate $id – check if collection with "id" exists :)
        let $corpus := dutil:get-corpus($id)
        return
            (: there is something, that's a teiCorpus :)
            if ( $corpus/name() eq "teiCorpus" ) then

                (: return the collection by id :)
                local:corpus-to-collection($id)

            else
                (: if the corpus doesn't exist, return 404 Not found :)
                (
                    <rest:response>
                    <http:response status="404"/>
                    </rest:response>,
                    "Corpus '" || $id || "' does not exist!"
                )


  else (: id is not set, return root-collection "corpora" :)
    local:root-collection()
};

(:~
 : Root Collection "corpora"
 :
 : returns the root collection "corpora"
 :)
declare function local:root-collection() {
    (: Get the corpora, get info needed for the member-array :)
  let $corpora := collection($config:data-root)//tei:teiCorpus
  (: get all the ids – these has to evaluate the teiCorpus files, unfortunately :)
  let $corpus-ids := $corpora//tei:idno[@type eq "URI"][@xml:base eq "https://dracor.org/"]/string()
  let $members := array {
      for $corpus-id in $corpus-ids
      return local:collection-member-by-id($corpus-id)
    }

  (: response :)


  let $title := "DraCor Corpora"
  let $dublincore := map {}
  let $totalParents := 0
  let $totalChildren := count( $members?* )

  return
    map {
      "@context" : $ddts:context ,
      "@id": "corpora",
      "@type": "Collection" ,
      "dts:totalParents": $totalParents ,
      "dts:totalChildren": $totalChildren ,
      "totalItems": $totalChildren , (:! same as children:)
      "title": $title,
      "member" : $members
    }
};

(:~
 : Collection Member
 :
 : Get a member of a collection
 :)
declare function local:collection-member-by-id($id as xs:string) {
    (: get metadata on the corpus by util-function :)
    let $info :=  dutil:get-corpus-info-by-name($id)
    (: there is no function to get number of files in a collection and dutil:get-corpus-meta-data is very slow, so get the TEIs and count.. :)
    (: this is basically what the dutil-function does before evaluating the files :)
    let $corpus-collection := concat($config:data-root, "/", $id)
    let $teis := collection($corpus-collection)//tei:TEI
    (:for the collection info in the dts, we only need a number to put into  "dts:totalItems" and "dts:totalChildren" :)
    let $file-count := count($teis)
    let $name := $info?name
    (: would have to get more data, e.g. number of plays in the collection. important! :)
    order by $name
      return
        map {
          "@id" : $name ,
          "title" : $info?title ,
          "description" : $info?description ,
          "@type" : "Collection" ,
          "dts:totalParents": 1 ,
          "totalItems" : $file-count ,
          "dts:totalChildren" : $file-count
        }
};


(:~
 : Transform a DraCor-Corpus to a DTS-Collection – https://distributed-text-services.github.io/specifications/Collections-Endpoint.html#child-collection-containing-a-single-work
 :)
declare function local:corpus-to-collection($id as xs:string) {
    (: get metadata on the corpus by util-function :)
    let $info :=  dutil:get-corpus-info-by-name($id)
    (: there is no function to get number of files in a collection and dutil:get-corpus-meta-data is very slow, so get the TEIs and count.. :)
    (: this is basically what the dutil-function does before evaluating the files :)
    let $corpus-collection := concat($config:data-root, "/", $id)
    let $teis := collection($corpus-collection)//tei:TEI
    return
        (: response :)


  let $title := $info?title
  let $description := $info?description
  let $dublincore := map {}
  (: assumes that it's a corpus one level below root-collection  :)
  let $totalParents := 1
  let $totalChildren := count( $teis )
  let $totalItems := count( $teis )

  let $members := for $tei in $teis
    return local:teidoc-to-collection-member($tei)

  return
    map {
      "@context" : $ddts:context ,
      "@id": $id,
      "@type": "Collection" ,
      "dts:totalParents": $totalParents ,
      "dts:totalChildren": $totalChildren ,
      "totalItems" : $totalItems ,
      "title": $title,
      "description" : $description ,
      "member" : array {$members}
    }


};

(:~
 : Transform a DraCor-TEI-Document to a member in a DTS-Collection
 :)
declare function local:teidoc-to-collection-member($tei) {
    let $id := dutil:get-dracor-id($tei)
    let $titles := dutil:get-titles($tei)
    let $lang := $tei/@xml:lang/string()

    let $filename := util:document-name($tei)
    let $playname := substring-before($filename, ".xml")
    let $collection-name := util:collection-name($tei)
    let $corpusname := tokenize($collection-name, '/')[last()]

    (: todo: add more metadata to dublin core :)
    let $dublincore :=
        map {
            "dc:language" : $lang
        }

    let $dts-download := $ddts:api-base || "/corpora/" || $corpusname || "/play/" || $playname || "/tei"
    let $dts-passage := $ddts:documents-base || "?id=" || $id
    (: todo: add navigation endpoint! :)

    (: todo: do something here! :)
    let $dts-citeDepth := 1

    return
        map {
            "@id" : $id ,
            "@type": "Resource" ,
            "title" : $titles?main ,
            "dts:dublincore" : $dublincore ,
            "totalItems": 0 ,
            "dts:totalParents": 1 ,
            "dts:totalChildren": 0 ,
            "dts:passage": $dts-passage ,
            "dts:download": $dts-download ,
            "dts:citeDepth" : $dts-citeDepth

        }
};

xquery version "3.1";

(:
 : DTS Endpoint
 : This module implements the DTS (Distributed Text Services) API specification – https://distributed-text-services.github.io/specifications/
 : developed for the DTS Hackathon https://distributed-text-services.github.io/workshops/events/2021-hackathon/ by Ingo Börner
 :)

(: todo:
 : * Paginated Child Collection; Paginantion not implemented, will return Status code 501
 : * add dublin core metadata; only added language so far
 : * add navigation endpoint
 : :)



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
    "documents": "/dts/documents"
    (: "navigation" : "/dts/navigation" :)
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

(:~
 : DTS Collections Endpoint
 :
 : Get a collection according to the specification: https://distributed-text-services.github.io/specifications/Collections-Endpoint.html
 :
 : @param $id Identifier for a collection or document, e.g. "ger" for GerDraCor. Root collection can be requested by leaving the parameter out or explicitly requesting it with "corpora"
 : @param $page Page of the current collection’s members. Functionality is not implemented, will return 501 status code.
 : @param $nav Use value "parents" to request the parent collection in "members" of the returned JSON object. Default behaviour is to return children in "member"; explicitly requesting "children" will work, but is not explicitly implemented
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/dts/collections")
  %rest:query-param("id", "{$id}")
  %rest:query-param("page", "{$page}")
  %rest:query-param("nav", "{$nav}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function ddts:collections($id, $page, $nav)
as map() {

  (: check, if param $id is set -- request a certain collection :)
  if ( $id ) then

    (: if root-collection "corpora is explicitly requested by id = 'corpora'" :)
    if ( $id eq "corpora" ) then
        local:root-collection()
    (: could also be a single document :)
    else if ( matches($id, "^[a-z]+[0-9]+$") ) then
          if ( $page ) then
            (: paging on readable collection = single document is not supported :)
            (
                    <rest:response>
                    <http:response status="400"/>
                    </rest:response>,
                    "Paging is not possible on a single resource. Try without parameter 'page'!"
            )
            else if ( $nav eq 'parents') then
            (: requested the parent collection of a document :)
              local:child-readable-collection-with-parent-by-id($id)
            else
                (: display as a readable collection :)
                local:child-readable-collection-by-id($id)
    else
        (: requesting a collection, but not the root-collection :)
        (: evaluate $id – check if collection with "id" exists :)
        let $corpus := dutil:get-corpus($id)
        return
            (: there is something, that's a teiCorpus :)
            if ( $corpus/name() eq "teiCorpus" ) then
                (: should check for paging and nav :)
                if ( $page ) then
                    (: will probably not implement paging for the moment :)
                    (
                        <rest:response>
                        <http:response status="501"/>
                        </rest:response>,
                    "Paging on a collection is not implemented. Try without parameter 'page'!"
                    )
                    else


                    if ( $nav eq "parents")
                    then
                        (: requesting the corpus + its parent, which will be the root-collection in the dracor-context :)
                        local:corpus-to-collection-with-parent-as-member($id)
                    else
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
 : Helper function that returns the root collection "corpora"
 :
 :)
declare function local:root-collection()
as map() {
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
 : Helper function to generate the collection members to put into the "member" array, e.g. of the root collection
 :
 : @param $id Identifier
 :
 :)
declare function local:collection-member-by-id($id as xs:string)
as map() {
    (: get metadata on the corpus by util-function :)
    let $info :=  dutil:get-corpus-info-by-name($id)
    (: there is no function to get number of files in a collection and dutil:get-corpus-meta-data is very slow, so get the TEIs and count.. :)
    (: this is basically what the dutil-function does before evaluating the files :)
    let $corpus-collection := concat($config:data-root, "/", $id)
    let $teis := collection($corpus-collection)//tei:TEI
    (:for the collection info in the dts, we only need a number to put into  "dts:totalItems" and "dts:totalChildren" :)
    let $file-count := count($teis)
    let $name := $info?name
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
 : Corpus to Collection
 :
 : Helper function to transform a DraCor-Corpus to a DTS-Collection – https://distributed-text-services.github.io/specifications/Collections-Endpoint.html#child-collection-containing-a-single-work
 :
 : @param $id Identifier of the corpus, e.g. "ger"
 :
 :)
declare function local:corpus-to-collection($id as xs:string)
as map() {
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
  let $dublincore := map {} (: still need to add information here, e.g. the title? :)
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
 : Document to collection member
 :
 : Helper function to transform a DraCor-TEI-Document to a member in a DTS-Collection.
 :
 : @param $tei TEI representation of a play
 :
 :)
declare function local:teidoc-to-collection-member($tei as element(tei:TEI) )
as map() {
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

(:~
 : Document as child readable collection (resource)
 :
 : Helper function to return a single document, that has been requested via the collections endpoint – see Child Readable Collection (i.e. a textual Resource)
 :
 : @param $id Identifier of the document, e.g. "ger000278"
 :
 :)
declare function local:child-readable-collection-by-id($id as xs:string)
as map() {
  let $tei := collection($config:data-root)//tei:idno[@type eq "dracor"][./text() eq $id]/root()/tei:TEI
  return
      if ( $tei ) then
      map:merge( (map {"@context" : $ddts:context } , local:teidoc-to-collection-member($tei)) )
      else
        (
                    <rest:response>
                    <http:response status="404"/>
                    </rest:response>,
                    "Resource '" || $id || "' does not exist!"
        )
};

(:~
 : Display single resource and add parent collection as member
 :)
declare function local:child-readable-collection-with-parent-by-id($id as xs:string) {
    let $self := local:child-readable-collection-by-id($id)
    (: must change map and add totalItems == 1 because of parent collection will be added as a member :)
    let $self-without-totalItems := map:remove($self, "totalItems")
    let $self-with-new-totalItems := map:merge( ( $self-without-totalItems, map{"totalItems" : 1})  )
    (: get parent collection and remove the members :)
    let $parent-collection-uri := util:collection-name(collection($config:data-root)//tei:idno[@type eq "dracor"][./text() eq $id])
    let $parent-collection-id := tokenize($parent-collection-uri,'/')[last()]
    (: get the parent by the function to generate a collection :)
    let $parent := local:corpus-to-collection($parent-collection-id)
    (: remove "members" and "@context" :)
    let $parent-without-members := map:remove($parent,"member")
    let $parent-withou-context := map:remove($parent-without-members, "@context")
    let $members := map {"member" : array { $parent-withou-context }}
    return
        map:merge(($self-with-new-totalItems, $members))
};


(:~
 : Parent Collection of a corpus
 :
 : Helper function to get a corpus with information on parent collection (will always be the root collection)
 :
 : @param $id Identifier of the collection, e.g. "ger"
 :
 :)
declare function local:corpus-to-collection-with-parent-as-member($id as xs:string)
as map() {
    let $self := local:corpus-to-collection($id)
    (: remove the members and the totalItems; set value of totalItems to one because there is only one root-collection  :)
    let $self-without-members := map:remove($self, "member")
    let $self-without-totalItems := map:remove($self-without-members, "totalItems")
    let $prepared-self := map:merge(( $self-without-totalItems, map{"totalItems" : 1} ))

    (: get the root collection and prepare :)
    let $parent := local:root-collection()
    (: remove the members :)
    let $parent-without-members := map:remove($parent, "member")
    (: remove "@context" :)
    let $prepared-parent := map:remove($parent-without-members, "@context")

    let $member := map { "member" : array { $prepared-parent } }

    (: merge the maps :)
    let $result := map:merge( ($prepared-self, $member) )

    return $result
};

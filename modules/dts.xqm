xquery version "3.1";

(:
 : DTS Endpoint
 : This module implements the DTS (Distributed Text Services) API specification – https://distributed-text-services.github.io/specifications/
 : developed for the DTS Hackathon https://distributed-text-services.github.io/workshops/events/2021-hackathon/ by Ingo Börner
 :)

(: todo:
 : * Paginated Child Collection; Paginantion not implemented, will return Status code 501
 : * add dublin core metadata; only added language so far
 : * didn't manage to implement all fields in the link header on all levels when requesting a fragment
 : * citeStructure: does it represent the structure, e.g. the types, or is it like a TOC, e.g. list all five acts in a five act play? needs to be refactored
 : * add machine readble endpoint documentation
 : * code of navigation endpoint should be refactored, maybe also code of documents endpoint (fragments)
 : :)



(: ddts – DraCor-Implementation of DTS follows naming conventions, e.g. dutil :)
module namespace ddts = "http://dracor.org/ns/exist/v1/dts";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";
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
declare variable $ddts:api-base := $config:api-base || "/dts"; 
declare variable $ddts:collections-base := $ddts:api-base || "/collection"  ;
declare variable $ddts:documents-base := $ddts:api-base || "/document" ;
declare variable $ddts:navigation-base := $ddts:api-base || "/navigation" ;

declare variable $ddts:ns-dts := "https://w3id.org/dts/api#" ;
declare variable $ddts:ns-hydra := "https://www.w3.org/ns/hydra/core#" ;
declare variable $ddts:ns-dc := "http://purl.org/dc/terms/" ;
declare variable $ddts:dts-jsonld-context-url := "https://distributed-text-services.github.io/specifications/context/1-alpha1.json" ;
declare variable $ddts:spec-version :=  "1-alpha" ; 

(: fixed parts in response, e.g. namespaces :)
(: TODO: check, maybe these need fixing for alpha!!:)
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
 : see https://distributed-text-services.github.io/specifications/versions/1-alpha/#entry-endpoint
 : /api//v1/dts
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
  %rest:path("/v1/dts")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ddts:entry-point() {
    (:  
    Implemented it like the example response here: https://distributed-text-services.github.io/specifications/versions/1-alpha/#entry-endpoint
    Can we use full URIs here or are these always relative paths?
    TODO: need to check which params are available on the endpoints in the final implementation
    and adapt the URI templates accordingly
    What happend to param level in the navigation endpoint?
    :)
    let $collection-template := $ddts:collections-base || "{?id}"
    let $document-template := $ddts:documents-base || "{?resource,ref}"
    let $navigation-template := $ddts:navigation-base || "{?resource,ref}"
    
    return
    map {
        "@context": $ddts:dts-jsonld-context-url,
        "@id": $ddts:api-base,
        "@type": "EntryPoint",
        "dtsVersion" : $ddts:spec-version,
        "collection": $collection-template,
        "document": $document-template,
        "navigation" : $navigation-template
    }
};

(:~
 : Calculate citeDepth
 :
 : Helper function to get citeDepth of a document
 : Can currently cite maximum structure of tei:body/tei:div/tei:div --> 3 levels, but not all dramas have the structure text proper - act - scene
 :
 :   :)
declare function local:get-citeDepth($tei as element(tei:TEI))
as xs:integer {
    if ( $tei//tei:body/tei:div/tei:div ) then 3
    else if ( $tei//tei:body/tei:div ) then 2
    else if ( $tei//tei:body ) then 1
    else 0
};

(:
 : --------------------
 : Collection Endpoint
 : --------------------
 :
 : see https://distributed-text-services.github.io/specifications/versions/1-alpha/#collection-endpoint
 : could be /api/v1/dts/collection
 :)

(:~
 : DTS Collection Endpoint
 :
 : Get a collection according to the specification: https://distributed-text-services.github.io/specifications/versions/1-alpha/#collection-endpoint
 :
 : @param $id Identifier for a collection or document, e.g. "ger" for GerDraCor. Root collection can be requested by leaving the parameter out or explicitly requesting it with "corpora"
 : @param $page Page of the current collection’s members. Functionality is not implemented, will return 501 status code.
 : @param $nav Use value "parents" to request the parent collection in "members" of the returned JSON object. Default behaviour is to return children in "member"; explicitly requesting "children" will work, but is not explicitly implemented
 :
 : @result JSON object
 :)
declare
  %rest:GET
  %rest:path("/v1/dts/collection")
  %rest:query-param("id", "{$id}")
  %rest:query-param("page", "{$page}")
  %rest:query-param("nav", "{$nav}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ddts:collections($id, $page, $nav)
{
(: had to remove the return type annotation because in case of an error it created a server error; was as map();
but in case of an error it is a sequence! :)    

  (: check, if param $id is set -- request a certain collection :)
  if ( $id ) then

    (: if root-collection "corpora is explicitly requested by id = 'corpora'" :)
    if ( $id eq "corpora" ) then
        local:root-collection()
    (: could also be a single document :)
    (: this regex check might not be a good idea, e.g if if use ger1 a thing that does not exist it still tries to find it :)
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
                (: This currently causes a server errror :)
                local:child-readable-collection-by-id($id)
    else
        (: requesting a collection, but not the root-collection :)
        (: evaluate $id – check if collection with "id" exists :)
        let $corpus := dutil:get-corpus($id)
        return
            (: there is something, that's a teiCorpus :)
            (: this is causing a problem because the check doesn't really check if the corpus exists :)
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
                (: Strangely, this does not trigger when using a non existent corpus id :)
                (
                    <rest:response>
                        <http:response status="404"/>
                    </rest:response>,
                    "The requested resource '" || $id ||  "' is not available."
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
  let $corpora := collection($config:corpora-root)//tei:teiCorpus
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
      "@context": $ddts:dts-jsonld-context-url ,
      "@id": "corpora",
      "@type": "Collection" ,
      "dtsVersion": $ddts:spec-version ,
      "totalItems": $totalChildren , (:! same as children:)
      "totalParents": $totalParents ,
      "totalChildren": $totalChildren ,
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
    let $corpus-collection := concat($config:corpora-root, "/", $id)
    let $teis := collection($corpus-collection)//tei:TEI
    (:for the collection info in the dts, we only need a number to put into  "dts:totalItems" and "dts:totalChildren" :)
    let $file-count := count($teis)
    let $name := $info?name
    order by $name
      return
        map {
          "@id" : $name ,
          "@type" : "Collection" ,
          "title" : $info?title ,
          "description" : $info?description ,
          "totalItems" : $file-count ,
          "totalParents": 1 ,
          "totalChildren" : $file-count
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
    let $corpus-collection := concat($config:corpora-root, "/", $id)
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
      "@context" : $ddts:dts-jsonld-context-url ,
      "@id": $id,
      "@type": "Collection" ,
      "dtsVersion": $ddts:spec-version ,
      "totalItems" : $totalItems ,
      "totalParents": $totalParents ,
      "totalChildren": $totalChildren ,
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
    let $paths := dutil:filepaths(base-uri($tei))
    let $playname := $paths?playname
    let $collection-name := util:collection-name($tei)
    let $corpusname := $paths?corpusname

    (: todo: add more metadata to dublin core :)
    let $authors := dutil:get-authors($tei)
    let $dc-creators := for $author in $authors return $author?name
    (: TODO: need to rework this! Removed it from the output for now :)
    let $dublincore :=
        map {
            "dc:creator" : $dc-creators ,
            "dc:language" : $lang
        }

    let $dts-download := $ddts:api-base || "/corpora/" || $corpusname || "/plays/" || $playname || "/tei"
    
    (: This actually need to be URI templates, not URLs, but to implement this, 
    we need to know which params the endpoints are supporting :)
    let $dts-document := $ddts:documents-base || "?resource=" || $id
    let $dts-navigation := $ddts:navigation-base || "?resource=" || $id

    (: todo: do something here! :)
    (: citeDepth seems to be deprecated; might to switch to citationTree or whatever :)
    let $dts-citeDepth := local:get-citeDepth($tei)

    return
        map {
            "@id" : $id ,
            "@type": "Resource" ,
            "title" : $titles?main ,
            "totalItems": 0 ,
            "totalParents": 1 ,
            "totalChildren": 0 ,
            (: "dublinCore" : $dublincore , :)
            (: the new things are called:)
            "document" : $dts-document, 
            "navigation" : $dts-navigation,
            "download": $dts-download 
            (:, "dts:citeDepth" : $dts-citeDepth :)

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
{
    (: Need to remove the return type annotation b/c in case of an error this fails :)
  
  (: Retrieve the TEI file:)
  let $tei := collection($config:corpora-root)/tei:TEI[@xml:id = $id]
  
  (: The line below causes problems if there this is not a valid ID :)
  
  
  return
      if ( $tei/name() eq "TEI" ) then
        
        let $cite-structure := local:generate-citeStructure($tei) return

            (: removed the citeStructure for now :)
            map:merge( 
                (map {"@context" : $ddts:dts-jsonld-context-url, "dtsVersion" : $ddts:spec-version } , 
                local:teidoc-to-collection-member($tei) 
                (: , $cite-structure :) ) )
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
    let $parent-collection-uri := util:collection-name(collection($config:corpora-root)//tei:idno[@type eq "dracor"][./text() eq $id])
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

(:~
:)
declare function local:generate-citationTree($tei as element(tei:TEI)) 
as map() {
 "Not implemented"
};

(:~
 :
 : Helper Function that generates dts:citeStructure to be included in the collection endpoint when requesting a resource
 : Deprecated, maybe; alpha-1 introduced citation trees!
 :
 : @param $tei TEI file
 :
 : :)
declare function local:generate-citeStructure($tei as element(tei:TEI) )
as map() {
    (: example https://distributed-text-services.github.io/specifications/Collections-Endpoint.html#child-readable-collection-ie-a-textual-resource :)

    (:
    "dts:citeStructure": [
        {
            "dts:citeType": "front"
        },
        {
            "dts:citeType": "poem",
            "dts:citeStructure": [
                {
                    "dts:citeType": "line"
                }
            ]
        }
    ]
    :)

    let $set := if ($tei//tei:front/tei:set) then ("set") else ()
    let $front-structure-types :=

        if ($tei//tei:front) then
            array {
                for $front-sub-structure-type in (distinct-values($tei//tei:front/tei:div/@type/string() ), $set)
                return
                    map{ "dts:citeType": lower-case($front-sub-structure-type) }
            }
        else()

    let $front-structure := map { "dts:citeType" : "front" , "dts:citeStructure" : $front-structure-types }

    let $body-structure :=
        (: structure body - act - scene :)
        if ($tei//tei:body/tei:div[@type eq "act"] and $tei//tei:body/tei:div/tei:div[@type eq "scene"]) then
            map { "dts:citeType" : "body" ,
                "dts:citeStructure" : array{ map{ "dts:citeType" : "act" , "dts:citeStructure" : array { map {"dts:citeType" : "scene" }  }  } }
                }
        (: structure: body – scene :)
        else if ( $tei//tei:body/tei:div[@type eq "scene"] ) then
            map { "dts:citeType" : "body" ,
                "dts:citeStructure" : array{ map{ "dts:citeType" : "scene" } } }
        (: structure: body - act, no scene :)
        else if ( $tei//tei:body/tei:div[@type eq "act"] and not($tei//tei:body/tei:div/tei:div) ) then
            map { "dts:citeType" : "body" ,
                "dts:citeStructure" : array{ map{ "dts:citeType" : "act"  } } }

        (: other types than scenes and acts ... :)
        else if ( $tei//tei:body/tei:div[@type]/tei:div[@type] ) then
            let $types-1 := distinct-values($tei//tei:body/tei:div/@type/string() )
            let $types-2 := distinct-values( $tei//tei:body/tei:div[@type]/tei:div/@type/string() )
            return
                (: structure, like act and scene, only with different type-values :)
                if ( (count($types-1) = 1) and (count($types-2) = 1) ) then
                    map { "dts:citeType" : "body" ,
                "dts:citeStructure" : array{ map{ "dts:citeType" : lower-case($types-1) , "dts:citeStructure" : array { map {"dts:citeType" : lower-case($types-2) }  }  } }
                }


                else ()


        (: structure: only body :)
        else if ( $tei//tei:body  and not($tei//tei:body/tei:div[@type eq "act"]) and not($tei//tei:body/tei:div[@type eq "scene"]) ) then
            map { "dts:citeType" : "body" }
        else ()

    let $back-structure :=
        if ($tei//tei:back) then map{ "dts:citeType": "back"} else ()

    let $cite-structure := array {$front-structure, $body-structure,  $back-structure}

    return

    map {"dts:citeStructure" : $cite-structure }
};


(:
 : --------------------
 : Document Endpoint
 : --------------------
 :
 : see https://distributed-text-services.github.io/specifications/Documents-Endpoint.html
 : could be /api/dts/documents (the specification uses "document", but mixes singular an plural; entry point will return "documents" in plural form, but this might change)
 :
 : MUST return "application/tei+xml"
 : will implement only GET
 :
 : Params:
 : $id	(Required) Identifier for a document. Where possible this should be a URI
 : $ref	Passage identifier (used together with id; can’t be used with start and end)
 : $start (For range) Start of a range of passages (can’t be used with ref)
 : $end (For range) End of a range of passages (requires start and no ref)
 : $format (Optional) Specifies a data format for response/request body other than the default
 :
 : Params used in POST, PUT, DELETE requests are not availiable

 :)

(:~
 : DTS Document Endpoint
 :
 : Get a document according to the specification: https://distributed-text-services.github.io/specifications/Documents-Endpoint.html
 :
 : @param $id Identifier for a document
 : @param $ref Passage identifier (used together with id; can’t be used with start and end)
 : @param $start (For range) Start of a range of passages (can’t be used with ref)
 : @param $end (For range) End of a range of passages (requires start and no ref)
 : @param $format (Optional) Specifies a data format for response/request body other than the default
 :
 : @result TEI
 :)
declare
  %rest:GET
  %rest:path("/v1/dts/documents")
  %rest:query-param("id", "{$id}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("format", "{$format}")
  %rest:produces("application/tei+xml")
  %output:media-type("application/xml")
  %output:method("xml")
function ddts:documents($id, $ref, $start, $end, $format) {
    (: check, if valid request :)

    (: In GET requests one may either provide a ref parameter or a pair of start and end parameters. A request cannot combine ref with the other two. If, say, a ref and a start are both provided this should cause the request to fail. :)
    if ( $ref and ( $start or $end ) ) then
        (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        <error statusCode="400" xmlns="https://w3id.org/dts/api#">
            <title>Bad Request</title>
            <description>GET requests may either have a 'ref' parameter or a pair of 'start' and 'end' parameters. A request cannot combine 'ref' with the other two.</description>
        </error>
        )
    else if ( ($start and not($end) ) or ( $end and not($start) ) ) then
        (: requesting a range, should check, if start and end is present :)
        (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        <error statusCode="400" xmlns="https://w3id.org/dts/api#">
            <title>Bad Request</title>
            <description>If a range is requested, parameters 'start' and 'end' are mandatory.</description>
        </error>
        )
    else if ( $format ) then
        (: requesting other format than TEI is not implemented :)
        (
        <rest:response>
            <http:response status="501"/>
        </rest:response>,
        <error statusCode="501" xmlns="https://w3id.org/dts/api#">
            <title>Not implemented</title>
            <description>Requesting other format than 'application/tei+xml' is not supported.</description>
        </error>
        )
        (: handled common errors, should check, if document with a certain $id exists :)

    else
        (: valid request :)
        let $tei := collection($config:corpora-root)/tei:TEI[@xml:id = $id]

        return
            (: check, if document exists! :)
            if ( $tei/name() eq "TEI" ) then
                (: here are valid requests handled :)

                if ( $ref ) then
                    (: requested a fragment :)
                    local:get-fragment-of-doc($tei, $ref)


                else if ( $start and $end ) then
                    (: requested a range; could be implemented, but not sure, if I will manage in time :)
                    (
                    <rest:response>
                        <http:response status="501"/>
                        </rest:response>,
                    <error statusCode="501" xmlns="https://w3id.org/dts/api#">
                        <title>Not implemented</title>
                        <description>Requesting a range is not supported.</description>
                    </error>
                    )

                else
                (: requested full document :)
                    local:get-full-doc($tei)

            else
                if ( not($id) or $id eq "" ) then
                    (: return the URI template/self description :)
                    local:collections-self-describe()
                else
                (: document does not exist, return the error :)
                (
        <rest:response>
            <http:response status="404"/>
        </rest:response>,
        <error statusCode="404" xmlns="https://w3id.org/dts/api#">
            <title>Not Found</title>
            <description>Document with the id '{$id}' does not exist!</description>
        </error>
        )

};

(: The URI template, that would be the self description of the endpoint – unclear, how this should be implemented :)
(: should include a link to a machine readable documentation :)
declare function local:collections-self-describe() {
    (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        <error statusCode="400" xmlns="https://w3id.org/dts/api#">
            <title>Bad Request</title>
            <description>Should at least use the required parameter 'id'. Automatic self description is not availiable.</description>
        </error>
        )
};

(:
 : Return full document requested via the documents endpoint :)
declare function local:get-full-doc($tei as element(tei:TEI)) {
    let $id := $tei/@xml:id/string()
    (: requested complete document, just return the TEI File:)
                (: must include the link header as well :)
                (: see https://distributed-text-services.github.io/specifications/Documents-Endpoint.html#get-responses :)
                (: see https://datatracker.ietf.org/doc/html/rfc5988 :)
                (: </navigation?id={$id}>; rel="contents", </collections?id={$id}>; rel="collection" :)
                let $links := '<' || $ddts:navigation-base || '?id=' || $id || '>; rel="contents", <' || $ddts:collections-base  ||'?id=' || $id || '>; rel="collection"'

                let $link-header :=  <http:header name='Link' value='{$links}'/>

                return
                (
                <rest:response>
                    <http:response status="200">
                       {$link-header}
                    </http:response>
                </rest:response>,
                $tei
                )
};

(:~
 : Return a document fragment
 :
 : @param $tei TEI of the Document
 : @param $ref identifier of the fragment requested
 : :)
declare function local:get-fragment-of-doc($tei as element(tei:TEI), $ref as xs:string) {
    let $id := $tei/@xml:id/string()

    let $fragment :=
        switch($ref)
        (: structures on level 1 :)
        case "front" return $tei//tei:front
        case "body" return $tei//tei:body
        case "back" return $tei//tei:back
        default return
            (: sorry for that, maybe use else if :)
            (: structures on level 2 :)

            (: front structures level 2 :)
            (: div:)
            if ( matches($ref, '^front.div.\d+$') ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                $tei//tei:front/tei:div[$pos]
            (: tei:set in tei:front :)
            else if ( matches($ref, '^front.set.\d+$') ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                    $tei//tei:front/tei:set[$pos]

            (: body structures level 2 :)
            else if ( matches($ref, "^body.div.\d+$") ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                    $tei//tei:body/tei:div[$pos]

            (: back structures level 2 :)
            else if ( matches($ref, "^back.div.\d+$") ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                    $tei//tei:back/tei:div[$pos]

            (: structures on level 3:)
            else if ( matches($ref, "body.div.\d+.div.\d+$") ) then
                let $div1-pos := xs:integer(tokenize($ref, "\.")[3])
                let $div2-pos := xs:integer(tokenize($ref, "\.")[last()])
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]

            (: not matched by any rule :)
            else()

    (: Link Header – see https://distributed-text-services.github.io/specifications/Documents-Endpoint.html#get-responses :)

    let $link-header := local:link-header-of-fragment($tei,$ref)


    return
        if ( not($fragment) ) then
            (
                <rest:response>
                    <http:response status="404"/>
                </rest:response>,
                <error statusCode="404" xmlns="https://w3id.org/dts/api#">
                    <title>Not found</title>
                    <description>Fragment with the identifier '{$ref}' does not exist.</description>
                </error>
            )
        else

            (
                <rest:response>
                    <http:response status="200">
                       {$link-header}
                    </http:response>
                </rest:response>,

                <TEI xmlns="http://www.tei-c.org/ns/1.0">
                    <dts:wrapper xmlns:dts="https://w3id.org/dts/api#">
                        {$fragment}
                    </dts:wrapper>
                </TEI>
            )
};

(:~
 :
 : Link Header
 :
 : Generates the Link Header needed for the response of the Document endpoint when requesting a fragment
 : @param $tei TEI Document (full doc)
 : @param $ref Identifier of the fragment
 :
 : :)
declare function local:link-header-of-fragment($tei as element(tei:TEI), $ref as xs:string) {

    (: need to generate:
    * prev	Previous passage of the document in the Document endpoint
    * next	Next passage of the document in the Document endpoint
    * up	Parent passage of the document in the Document endpoint. If the current request is already for the entire document, no up link will be provided. If the only parent is the entire document, the up value will link to the document as a whole.
    * first	First passage of the document in the Document endpoint
    * last	The URL for the last passage of the document in the Document endpoint
    * contents	The URL for the Navigation Endpoint for the current document
    * collection	The URL for the Collection endpoint for the current document
    :)

    let $doc-id := $tei/@xml:id/string()

    let $collection-val := $ddts:collections-base || "?id=" || $doc-id
    let $collection := '<' || $collection-val  || '>; rel="collection"'

    let $contents-val := $ddts:navigation-base || "?id=" || $doc-id
    let $contents := '<' || $contents-val || '>; rel="contents"'

    (: some parts of the link header depend on the level of the structure :)
    (: level1 structures tei:front, tei:body, tei:back :)

    let $up :=
        if ( matches($ref, "^((front)|(body)|(back))$" ) ) then
            let $up-val := $ddts:documents-base || "?id=" || $doc-id
            return '<' || $up-val || '>; rel="up"'
        else if ( matches($ref, "^((front)|(body)|(back))\.((div)|(set)).\d+$") ) then
            let $parent-id := tokenize($ref,"\.")[1]
            let $up-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $parent-id
            return '<' || $up-val || '>; rel="up"'
        else if ( matches($ref, "^body\.div\.\d+\.div\.\d+$") ) then
            let $parent-div-no := tokenize($ref,'\.')[last()-2]
            let $parent-id := "body.div." || $parent-div-no
            let $up-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $parent-id
            return '<' || $up-val || '>; rel="up"'
        else ()

    let $first :=
        if ( matches($ref, "^((front)|(body)|(back))$" ) ) then
            let $first-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || "front"
            return '<' || $first-val || '>; rel="first"'
        else if ( matches($ref, "^((front)|(body)|(back))\.((div)|(set)).\d+$") ) then
            let $parent-id := tokenize($ref,"\.")[1]
            let $first-id := $parent-id || ".div.1"
            let $first-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $first-id
            return '<' || $first-val || '>; rel="first"'
         else if ( matches($ref, "^body\.div\.\d+\.div\.\d+$") ) then
            let $parent-div-no := tokenize($ref,'\.')[last()-2]
            let $parent-id := "body.div." || $parent-div-no
            let $first-id := $parent-id || ".div.1"
            let $first-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $first-id
            return '<' || $first-val || '>; rel="first"'
    else ()

    let $last :=
        if ( matches($ref, "^((front)|(body)|(back))$" ) ) then
            let $last-id := if ( $tei//tei:back) then "back" else "body"
            let $last-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $last-id
            return '<' || $last-val || '>; rel="last"'
        else if ( matches($ref, "^body\.div.\d+$") ) then
            (: only implemented this for body – last act/scene :)
            let $last-no := count( $tei//tei:body/tei:div) => xs:string()
            let $last-id := "body.div." || $last-no
            let $last-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $last-id
            return '<' || $last-val || '>; rel="last"'
          (: following code doesn't work, somehow counts all scenes; todo: fixme! :)
          (:
        else if ( matches($ref, "^body\.div\.\d+\.div\.\d+$") ) then

            let $parent-div-no := tokenize($ref,'\.')[last()-2]
            let $last-no := count( $tei//tei:body/tei:div[$parent-div-no]/tei:div ) => xs:string()
            let $last-id := "body.div." || xs:string($parent-div-no) || ".div." || $last-no
            let $last-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $last-id
            return '<' || $last-val || '>; rel="last"'
            :)
        else ()

    let $prev :=
        if ( matches($ref, "^front$") ) then
            ()
        else if ( matches($ref, "^body$") ) then
            let $prev-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || "front"
            return '<' || $prev-val || '>; rel="prev"'
        else if ( matches($ref, "^back$") ) then
            let $prev-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || "body"
            return '<' || $prev-val || '>; rel="prev"'
        (: only implemented this for body :)
        else if ( matches($ref, "^body\.div.\d+$") ) then
            let $this-no := tokenize($ref, '\.')[last()] => xs:integer()
            let $prev-no := $this-no - 1
            return
            if ( $prev-no > 0 ) then
                let $prev-id := "body.div." || $prev-no
                let $prev-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $prev-id
                 return '<' || $prev-val || '>; rel="prev"'
            else ()
        else if ( matches($ref, "^body\.div\.\d+\.div\.\d+$") ) then
            let $parent-div-no := tokenize($ref,'\.')[last()-2]
            let $this-div-no := tokenize($ref, '\.')[last()] => xs:integer()
            let $prev-div-no := $this-div-no - 1
                return
            if ( $prev-div-no > 0 ) then
                let $prev-id := "body.div." || $parent-div-no || ".div." || $prev-div-no
                let $prev-val := $ddts:documents-base || "?id=" || $doc-id || "&amp;" || "ref=" || $prev-id
                 return '<' || $prev-val || '>; rel="prev"'
            else ()

        else ()


    (: todo: implement next :)
    let $next := ()

    let $link-header-value := string-join( ($contents,$collection, $up, $first, $last, $prev, $next), ", " )
    let $link-header := <http:header name='Link' value='{$link-header-value}'/>
    return
        $link-header
};

(:
 : --------------------
 : Navigation Endpoint
 : --------------------
 :
 : see https://distributed-text-services.github.io/specifications/Navigation-Endpoint.html
 : could be /api/dts/navigation
 :)


 (:~
 : DTS Navigation Endpoint
 :
 : @param $id Identifier of the resource being navigated
 : @param $ref ... todo: add from spec
 : @param $level ... todo: add from spec
 :
 : @result JSON Object
 :)
 declare
  %rest:GET
  %rest:path("/v1/dts/navigation")
  %rest:query-param("id", "{$id}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("level", "{$level}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
 function ddts:navigation($id, $ref, $level) {
    (: parameter $id is mandatory :)
    if ( not($id) ) then
        (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        "Mandatory parameter 'id' is missing."
        )
    else
        (: check, if there is a resource with this identifier :)
        let $tei := collection($config:corpora-root)/tei:TEI[@xml:id = $id]

        return
            (: check, if document exists! :)
            if ( $tei/name() eq "TEI" ) then
                (: here are valid requests handled :)
 
                (:
                in the case of DraCor, it makes sense to be able to request a TEI representation of the tei:castList,
                this could be the first level, e.g. the division of tei:front and tei:body – which contains the text proper;
                so first level (of structural division) would contain only tei:front, tei:body, tei:back; fragment ids would be {dracorID}.front, {dracorID}.body, {dracorID}.back
                :)
                (: Level 1 :)
                if ( not($ref) and not($level) ) then
                    local:navigation-level1($tei)

                (: Level 2 :)
                (: in the case of tei:front, would contain the divisions tei:div of tei:front, which is also the tei:castList :)
                (: in the case of tei:body, it would be the top-level divisions of the body, normally "acts" – could also be "scenes" if there are no "acts"... but this case must be handled separately :)
                else if ( $level and not($ref) ) then
                    local:navigation-level-n($tei, $level)

                (: Level 3 :)
                (: don't care about tei:front here, but in the case of a drama with acts and scenes in the tei:body, this would normally list the "scenes" :)

                (: Level 4 :)
                (: in the boilerplate play front/body - acts - scenes, this would return the structural divisions like speeches and stage directions :)

                (: we will have to see, if this will work out like this; I might implement it for this case and return only level zero, e.g. the whole document, if it doesn't fit this pattern :)
                (: special case, that is implemented: ref is a level 1 division of body, e.g. an act, will return the scenes of this act. :)
                else if ( $ref and (not($level) or ($level eq "1")) ) then
                    local:children-of-subdivision($tei, $ref)


                (: there is also a conflicting hierarchy, e.g. Pages! which would be a second cite structure :)


                (: valid requests end above :)

                (: don't really know, when this could become true :)
                else (: maybe return invalid request? or 404 :)
                (
                <rest:response>
                    <http:response status="404"/>
                </rest:response>,
                "Requested cite structure does not exist or can't be resolved."
                )

            else
                (: not a valid id :)
                (
                <rest:response>
                    <http:response status="404"/>
                </rest:response>,
                "Document with the id '" ||  $id || "' does not exist."
                )
 };

 (: Generate such a Object that is used in the navigation endpoint and we will see, what are the challenges  :)
 declare function local:navigation-level1($tei as element(tei:TEI)) {
     (: see https://distributed-text-services.github.io/specifications/Navigation-Endpoint.html#example-1-requesting-top-level-children-of-a-textual-resource :)
     (: So the id parameter supplied in the query is the identifier of the Resource as a whole. :)

     (:
                in the case of DraCor, it makes sense to be able to request a TEI representation of the tei:castList,
                this could be the first level, e.g. the division of tei:front and tei:body – which contains the text proper;
                so first level (of structural division) would contain only tei:front, tei:body, tei:back; fragment ids would be {dracorID}.1.front, {dracorID}.1.body, {dracorID}.1.back
                :)
     let $doc-id := $tei/@xml:id/string()
     let $request-id := $ddts:navigation-base || "?id=" || $doc-id
     let $citeDepth := local:get-citeDepth($tei) (: needs to be generated by a function, evaluating structural information – a number defining the maximum depth of the document’s citation tree. E.g., if the a document has up to three levels, dts:citeDepth should be the number 3. :)
     let $level := 1 (: a number identifying the hierarchical level of the references listed in member, counted relative to the top of the document’s citation tree. E.g., if a the returned references are at the second hierarchical level (like {"dts:ref": "1.1"}) then the dts:level in the response should be the number 2. (The Resource as a whole is considered level 0.) :)
     let $parent := ()



     let $passage := $ddts:documents-base || "?id=" || $doc-id || "{&amp;ref}{&amp;start}{&amp;end}" (: the URI template to the Documents endpoint at which the text of passages corresponding to these references can be retrieved.:)

     (: ok, it's hardcoded, but tryin' ... :)
     let $member :=
        (
        if ($tei//tei:front) then map {"dts:ref": "front"} else () ,
        if ($tei//tei:body) then map {"dts:ref" : "body"} else (),
        if ($tei//tei:back) then map {"dts:ref" : "back"} else ()
        )


     return

     map{
         "@context" : $ddts:context ,
         "@id" : $request-id ,
         "dts:citeDepth" : $citeDepth ,
         "dts:level": $level ,
         "dts:passage":  $passage ,
         "dts:parent" : $parent ,
         "member" : array{$member}


     }
 };

 declare function local:navigation-level-n($tei as element(tei:TEI), $level as xs:string) {
     (: Example 2: Requesting all descendants of a textual Resource at a specified level - https://distributed-text-services.github.io/specifications/Navigation-Endpoint.html#example-2-requesting-all-descendants-of-a-textual-resource-at-a-specified-level :)
     let $doc-id := $tei/@xml:id/string()
     let $request-id := $ddts:navigation-base || "?id=" || $doc-id || "&amp;" || "level=" || $level
     let $citeDepth := local:get-citeDepth($tei) (: needs to be generated by a function, evaluating structural information – a number defining the maximum depth of the document’s citation tree. E.g., if the a document has up to three levels, dts:citeDepth should be the number 3. :)
     let $passage := $ddts:documents-base || "?id=" || $doc-id || "{&amp;ref}{&amp;start}{&amp;end}" (: the URI template to the Documents endpoint at which the text of passages corresponding to these references can be retrieved.:)



     return
     if ($level eq "1") then
         (: there is a designated function that handles level 1 :)
         local:navigation-level1($tei)

     (: Level 2 :)
     else if ( $level eq "2" ) then

        let $parent :=
            map {
                "@type": "Resource",
                "@dts:ref": $ddts:navigation-base || "?id=" || $doc-id
                }
  (: the unique passage identifier for the hierarchical parent of the current node in the document structure, defined by the ref query parameter. If the query specifies a range rather than a single ref, no parent should be specified and dts:parent should have a value of “null”. :)

        (: not sure, if front, body and back can be handled, using "union" :)
        (: should be put into a function?! :)
        (: tei:set is not wrapped in a div but should be on this level. Included it at the end, but this might 'destroy' the order of the segments in front; must be tackled at some other point :)
        let $front-segments := $tei//tei:front/tei:div
        let $front-members :=
            for $front-segment at $front-segment-pos in $front-segments
                let $front-segment-heading := $front-segment/tei:head[1]/string()
                let $front-segment-type := $front-segment/@type/string()
                let $front-segment-type-map := if ( $front-segment-type != '' ) then map{ "dts:citeType": lower-case($front-segment-type)  } else ()
                let $front-segment-id := "front" || "." || "div" || "." || string($front-segment-pos)
                let $front-segment-id-map := map { "dts:ref": $front-segment-id }
                return
                    map:merge( ($front-segment-id-map,$front-segment-type-map) )

        let $settings :=
            for $set at $set-pos in $tei//tei:front/tei:set
                let $set-type-map := map{ "dts:citeType": "setting"  }
                let $set-id := "front" || "." || "set" || "." || string($set-pos)
                let $set-id-map := map { "dts:ref": $set-id }
            return
                map:merge( ($set-id-map,$set-type-map) )

        let $body-segments := $tei//tei:body/tei:div
        let $body-members :=
            for $body-segment at $body-segment-pos in $body-segments
                let $body-segment-heading := $body-segment/tei:head[1]/string() => normalize-space()
                let $body-segment-title-map := map { "dc:title" : $body-segment-heading}
                let $body-segment-type := $body-segment/@type/string()
                let $body-segment-type-map := if ( $body-segment-type != '' ) then map{ "dts:citeType": lower-case($body-segment-type)  } else ()
                let $body-segment-id := "body" || "." || "div" || "." || string($body-segment-pos)
                let $body-segment-id-map := map { "dts:ref": $body-segment-id }
                let $body-dublincore-map := map { "dts:dublincore": $body-segment-title-map }
                return
                    map:merge( ($body-segment-type-map, $body-segment-id-map, $body-dublincore-map) )

        let $back-segments := $tei//tei:back/tei:div
        let $back-members :=
            for $back-segment at $back-segment-pos in $back-segments
                let $back-segment-heading := $back-segment/tei:head[1]/string()
                let $back-segment-type := $back-segment/@type/string()
                let $back-segment-type-map := if ( $back-segment-type != '' ) then map{ "dts:citeType": lower-case($back-segment-type)  } else ()
                let $back-segment-id := "back" || "." || "div" || "." || string($back-segment-pos)
                let $back-segment-id-map := map { "dts:ref": $back-segment-id }
                return
                    map:merge( ($back-segment-id-map, $back-segment-type-map) )

        return

        map{
         "@context" : $ddts:context ,
         "@id" : $request-id ,
         "dts:citeDepth" : $citeDepth ,
         "dts:level": xs:integer($level) ,
         "dts:passage":  $passage ,
         "dts:parent" : $parent ,
         "member" : array{$front-members, $settings, $body-members, $back-members}
        }

        (: end of level2 :)
     else
        (: this level is not implemented/not availiable :)
        (
            <rest:response>
                <http:response status="400"/>
            </rest:response>,
            "Level '" || $level || "' is not available."
        )
 };

(:~
 :
 : Can be used to retrieve children of an act; might not be too generic
 : :)
declare function local:children-of-subdivision($tei, $ref) {
    let $level := 3
    let $citeDepth := local:get-citeDepth($tei)
    let $doc-id := $tei/@xml:id/string()
    let $passage := $ddts:documents-base || "?id=" || $doc-id || "{&amp;ref}{&amp;start}{&amp;end}"

    return
    if ( matches($ref, "^body.div.\d+$") ) then
        let $parent := map {"@type": "CitableUnit", "dts:ref": "body" }
        (: get scenes of an act :)
        let $div-no := xs:integer(tokenize($ref,'\.')[last()])
        let $segments := $tei//tei:body/tei:div[$div-no]/tei:div
        let $members :=
            for $segment at $segment-pos in $segments
            let $segment-heading := $segment/tei:head[1]/string() => normalize-space()
            let $segment-title-map := map { "dc:title" : $segment-heading}
            let $segment-type := $segment/@type/string()
            let $segment-type-map := if ( $segment-type != '' ) then map{ "dts:citeType": lower-case($segment-type)  } else ()
            let $segment-id := $ref || "." || "div" || "." || xs:string($segment-pos)
            let $segment-id-map := map { "dts:ref": $segment-id }
            let $dublincore-map := map { "dts:dublincore": $segment-title-map }
                return
                    map:merge( ($segment-id-map, $dublincore-map, $segment-type-map) )

        let $request-id := $ddts:navigation-base || "?id=" || $doc-id || "&amp;" || "ref=" || $ref

        return
            (<rest:response>
                <http:response status="200"/>
            </rest:response>,
            map{
                "@context" : $ddts:context ,
                "@id" : $request-id ,
                "dts:citeDepth" : $citeDepth ,
                "dts:level": $level ,
                "dts:passage":  $passage ,
                "dts:parent" : $parent ,
                "member" : array{$members}
            }
            )


    else
        (
            <rest:response>
                <http:response status="501"/>
            </rest:response>,
            "Requesting children of any none-body div is not implemented."
        )

};

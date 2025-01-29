xquery version "3.1";

(:
 : DTS Endpoints

 : This module implements the DTS (Distributed Text Services) API Specification – https://distributed-text-services.github.io/specifications/
 : the original implementation was developed for the DTS Hackathon https://distributed-text-services.github.io/workshops/events/2021-hackathon/ by Ingo Börner
 : it was later revised to meet the updated specification of 1-alpha (see https://github.com/dracor-org/dracor-api/pull/172) 
 : or, more precisely, "unstable" as of December 2024.
 : 
 : The DTS-Validator (https://github.com/mromanello/DTS-validator) was used to test the endpoints, see Readme there on how to run locally;
 : pytest --entry-endpoint=http://localhost:8088/api/v1/dts --html=report.html
 : The validator does not use strict "1-alpha" but the later version "unstable". 
 : https://github.com/mromanello/DTS-validator/blob/main/NOTES.md#validation-reports-explained
 : In general the aim is to implement the spec in a way that the Validator does not raises any errors which as of Dec 16th 2024 is the case.
 :)

(: ddts – DraCor-Implementation of DTS follows naming conventions of the dracor-api, e.g. dutil :)
module namespace ddts = "http://dracor.org/ns/exist/v1/dts";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

(: Namespaces mentioned in the spec:  :)
declare namespace dts = "https://w3id.org/dts/api#";
declare namespace dc = "http://purl.org/dc/terms/";
(: there are others, see the JSON-LD context at https://distributed-text-services.github.io/specifications/context/1-alpha1.json 
: which are not in use here :)

(: Variables used in responses :)
declare variable $ddts:base-uri := replace($config:api-base, "/api/v1","") ;
declare variable $ddts:api-base := $config:api-base || "/dts";
declare variable $ddts:collections-base := $ddts:api-base || "/collection"  ;
declare variable $ddts:documents-base := $ddts:api-base || "/document" ;
declare variable $ddts:navigation-base := $ddts:api-base || "/navigation" ;

declare variable $ddts:ns-dts := "https://w3id.org/dts/api#" ;
declare variable $ddts:ns-dc := "http://purl.org/dc/terms/" ;
declare variable $ddts:dts-jsonld-context-url := "https://distributed-text-services.github.io/specifications/context/1-alpha1.json" ;

(: Implemented "unstable", needs to be changed when there is a stable version 1 :)
declare variable $ddts:spec-version :=  "unstable" ; 

(: JSON-ld context that (is) should be embedded in the responses:)
(: The @context is hardcoded at some other places so this might be deprecated. It is only used in the 
: also deprecated function local:navigation-level-n :)
declare variable $ddts:context := 
  map {
      "@context": $ddts:dts-jsonld-context-url
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
 : Implemented it like the example response here: https://distributed-text-services.github.io/specifications/versions/1-alpha/#entry-endpoint
 :
 : @result JSON object
 :
 : TODO: need to check which params are available on the endpoints in the final implementation
 : and adapt the URI templates accordingly, e.g. additional param 'page', but also currently not functional 'mediaType' and 'tree'.
 :)
declare
  %rest:GET
  %rest:path("/v1/dts")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
function ddts:entry-point() 
as map() {
    let $collection-template := $ddts:collections-base || "{?id,nav}"
    let $document-template := $ddts:documents-base || "{?resource,ref,start,end,mediaType}"
    let $navigation-template := $ddts:navigation-base || "{?resource,ref,start,end,down,tree}"
    
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
 : Can currently cite maximum structure of tei:body/tei:div/tei:div/tei:sp or tei:stage --> 4 levels,
 : but not all dramas have the structure text proper - act - scene. 
 : This only evaluates the tei:body element, but we can expect the body being the most complex part.
 :
 : @param $tei TEI of a play
 :
 : @result maximum depth of the citation tree
 :)
declare function local:get-citeDepth($tei as element(tei:TEI))
as xs:integer {
    if ( $tei//tei:body/tei:div/tei:div[tei:stage or tei:sp] ) then 4
    else if ( $tei//tei:body/tei:div[tei:stage or tei:sp] ) then 3
    else if ( $tei//tei:body[tei:stage or tei:sp] ) then 2 (: this should not exist! :)
    else 0
};

(:~ 
 : Convert DraCor URIs to DraCor IDs
 : 
 : The DTS Spec seems to favor the use of real URIs as identifiers. DraCor already resolve URIs 
 : of plays, https://dracor.org/id/gerXXXXXX; it would be logical to use them here as well
 :
 : @param $uri DraCor URI (can not work with /entity/ pattern!)
 :
 : @result DraCor ID
 :)
declare function local:uri-to-id($uri as xs:string) 
as xs:string {
    (:this might not be the best option, hope it works for now:)
    tokenize($uri,"/id/")[last()]
};

(:~ 
 : Covert IDs to URIs
 :
 : see local:uri-to-id, this does the inverse, e.g. identifiers playname (and corpusname) are turned
 : into URIs, e.g. gerXXXXXX becomes https://dracor.org/id/gerXXXXXX.
 : 
 : @param $id DraCor ID
 :
 : @result URI
 :)
declare function local:id-to-uri($id as xs:string)
as xs:string {
    (: might not be the ultimate best solution, hope it works for now :)
    $ddts:base-uri || "/id/" || $id
};


(:
 : --------------------
 : Collection Endpoint
 : --------------------
 :
 : see https://distributed-text-services.github.io/specifications/versions/1-alpha/#collection-endpoint
 : could be /api/v1/dts/collection

 : Question: There is a param "id" in the collection endpoint: Shall this be a full URI as well; this somehow maps to the
 : values of param "resource" in the other two endpoints

 :)

(:~
 : DTS Collection Endpoint
 :
 : Get a collection according to the specification: https://distributed-text-services.github.io/specifications/versions/1-alpha/#collection-endpoint
 :
 : @param $id Identifier for a collection or document, Should be a URI, forget this for 1-alpha: e.g. "ger" for GerDraCor. Root collection can be requested by leaving the parameter out or explicitly requesting it with "corpora"
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
function ddts:collections($id as xs:string*, $page as xs:string*, $nav as xs:string*)
as item()+ {
  (: check, if param $id is set -- request a certain collection :)
  if ( $id ) then

    (: if root-collection "corpora" is explicitly requested by id = 'corpora' :)
    (: this is somewhat a legacy behaviour before switching to 1-alpha and adressing everything by URIs :)
    (: we can still support it because, still, it feels natural to use only the corpusname to get a corpus :)
    if ( $id eq "corpora") then
        (: http://localhost:8088/api/v1/dts/collection?id=corpora :)
        local:root-collection()
    else if ( $id eq $ddts:base-uri ) then
        (: this would be the default to address the root collection :)
        (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088:)
        local:root-collection()

    else if ( matches($id, "^[a-z]+$") ) then
    (: this is a collection only, e.g. "ger" or "test" :)
        let $corpus := dutil:get-corpus($id)
        return
            if ( $page ) then
            (: Paging is currently not supported :)
            (: test: http://localhost:8088/api/v1/dts/collection?id=rus&page=1 :)
            (
                    <rest:response>
                    <http:response status="400"/>
                    </rest:response>,
                    "Paging is not possible on a single resource. Try without parameter 'page'!"
            )

            else if ($corpus/name() eq "teiCorpus") then 
                if ( $nav eq 'parents') then 
                    local:corpus-to-collection-with-parent-as-member($id)
                else    
                    local:corpus-to-collection($id)
            else
            (: A corpus with this ID does not exist :)
            (: test: http://localhost:8088/api/v1/dts/collection?id=foo :)
            (
                    <rest:response>
                        <http:response status="404"/>
                    </rest:response>,
                    "The requested resource (corpus) '" || $id ||  "' is not available."
            )
    else if ( matches($id, concat("^", $ddts:base-uri, "/id/","[a-z]+$" ) ) ) then
        (: A corpus = collection requested with URI as value of the id param :)
        let $corpusname := local:uri-to-id($id)
        let $corpus := dutil:get-corpus($corpusname)
        return
            if ($corpus/name() eq "teiCorpus") then 
                if ( $page ) then
                (: paging is currently not supported :)
                (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/rus&page=1 :)
                (
                    <rest:response>
                    <http:response status="400"/>
                    </rest:response>,
                    "Paging is not possible on a single resource (corpus). Try without parameter 'page'!"
                )


                else if ( $nav eq 'parents') then 
                
                (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/ger&nav=parents :)
                    local:corpus-to-collection-with-parent-as-member($id)
                
                else if ($nav and $nav != "parents" ) then
                (: sanity check the parameter "nav"; this could only be "parents" :)
                (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/ger&nav=foo :)
                    (
                        <rest:response>
                        <http:response status="400"/>
                        </rest:response>,
                        "The value '" || $nav || "' of the parameter 'nav' is not allowed. Use the single allowed value 'parents' if you want to request the parent collection."
                    )
                else
                (: the default behaviour :)
                (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/ger :)
                    local:corpus-to-collection($id)
            else
            (
                    <rest:response>
                        <http:response status="404"/>
                    </rest:response>,
                    "The requested resource (corpus) '" || $id ||  "' is not available."
            )

    (: in pre-alpha we used normal DraCor playnames or so; now everything should be adressed with real uris 
     : this is somewhat legacy behaviour, but will handle the original ids to be backwards
     : compatible, e.g. if someone request e.g. ger000001
    :)
    (: could also be a single document :)
    else if ( matches($id, "^[a-z]+[0-9]{6}$") ) then
          if ( $page ) then
            (: paging on readable collection = single document is not supported :)
            (: test: http://localhost:8088/api/v1/dts/collection?id=ger000171&page=1 :)
            (
                    <rest:response>
                    <http:response status="400"/>
                    </rest:response>,
                    "Paging is not possible on a single resource. Try without parameter 'page'!"
            )
            else if ( $nav eq 'parents') then
            (: requested the parent collection of a document :)
            (: test: http://localhost:8088/api/v1/dts/collection?id=ger000171&nav=parents :)
              local:child-readable-collection-with-parent-by-id($id)
            else if ( $nav and $nav != "parents") then
                (: Sanity Check $nav param, see https://github.com/mromanello/DTS-validator/blob/main/NOTES.md#validation-reports-explained :)
                (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/ger000171&nav=foo :)
                (
                        <rest:response>
                        <http:response status="400"/>
                        </rest:response>,
                    "The value '" || $nav || "' of the parameter 'nav' is not allowed. Use the single allowed value 'parents' if you want to request the parent collection."
                )
            else
                (: display as a readable collection :)
                (: test: http://localhost:8088/api/v1/dts/collection?id=ger000171 :)
                local:child-readable-collection-by-id($id)
    
    else if ( matches($id, concat("^", $ddts:base-uri, "/id/","[a-z]+[0-9]{6}$" ) ) ) then
    (: requested a single play with full URI – as it should be done :)
        let $playname := local:uri-to-id($id)
        return
            if ( $page ) then
            (: paging on readable collection = single document is not supported :)
            (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/ger000171&page=1 :)
            (
                    <rest:response>
                    <http:response status="400"/>
                    </rest:response>,
                    "Paging is not possible on a single resource. Try without parameter 'page'!"
            )
            else if ( $nav eq 'parents') then
            (: requested the parent collection of a document :)
            (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/ger000171&nav=parents :)
            local:child-readable-collection-with-parent-by-id($playname)
            else
                (: Sanity Check $nav param, see https://github.com/mromanello/DTS-validator/blob/main/NOTES.md#validation-reports-explained :)
                if ( $nav and $nav != 'parents' ) then
                (
                        <rest:response>
                        <http:response status="400"/>
                        </rest:response>,
                    "The value '" || $nav || "' of the parameter 'nav' is not allowed. Use the single allowed value 'parents' if you want to request the parent collection."
                )
                else
                (: display as a readable collection :)
                local:child-readable-collection-by-id($playname)
    

    
    else 
    (: Parameter id is set, but it is not a valid ID (not covered by the regexes) :)
    (: test: http://localhost:8088/api/v1/dts/collection?id=ger12345 :)
    (: test: http://localhost:8088/api/v1/dts/collection?id=http://localhost:8088/id/ger12345 :)
        (
            <rest:response>
                <http:response status="400"/>
            </rest:response>,
                    "The value '" || $id || "' of the parameter 'id' is not in a valid format: Either provide the id or URI of a corpus or play."
        )

  else 
  (: id is not set, return root-collection "corpora" :)
  (: test: http://localhost:8088/api/v1/dts/collection :)
  (: this fails: http://localhost:8088/api/v1/dts/collection/ :)
  (: tailing slashes suck! Don't use them! :)
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

  (: assemble the data of the response :)

  let $title := "DraCor Corpora"
  let $dublincore := map {}
  let $totalParents := 0
  let $totalChildren := count( $members?* )

  return
    map {
      "@context": $ddts:dts-jsonld-context-url ,
      "@id": $ddts:base-uri,
      "@type": "Collection" ,
      "dtsVersion": $ddts:spec-version ,
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
 : @param $id Identifier (This is actually a URI)
 :
 :)
declare function local:collection-member-by-id($id as xs:string)
as map() {
    let $corpusname := local:uri-to-id($id)
    (: get metadata on the corpus by util-function :)
    let $info :=  dutil:get-corpus-info-by-name($corpusname)
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
          "@id" : local:id-to-uri($id) , (: was name :)
          "@type" : "Collection" ,
          "title" : $info?title ,
          "description" : $info?description ,
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
    let $corpusname := local:uri-to-id($id)
    (: get metadata on the corpus by util-function :)
    let $info :=  dutil:get-corpus-info-by-name($corpusname)
    (: there is no function to get number of files in a collection and dutil:get-corpus-meta-data is very slow, so get the TEIs and count.. :)
    (: this is basically what the dutil-function does before evaluating the files :)
    let $corpus-collection := concat($config:corpora-root, "/", $corpusname)
    let $teis := collection($corpus-collection)//tei:TEI
    return
        (: response :)

  let $title := $info?title
  let $description := $info?description
  let $dublincore := map {} (: still need to add information here, e.g. the title? :)
  (: assumes that it's a corpus one level below root-collection  :)
  let $totalParents := 1
  let $totalChildren := count( $teis )
  
  (: The property "totalItems" has become deprecated in the "unstable" spec see also https://github.com/mromanello/DTS-validator/blob/main/NOTES.md#validation-reports-explained :)
  (: let $totalItems := count( $teis ) :)

  let $members := for $tei in $teis
    return local:teidoc-to-collection-member($tei)

  return
    map {
      "@context" : $ddts:dts-jsonld-context-url ,
      "@id": local:id-to-uri($corpusname), 
      "@type": "Collection" ,
      "dtsVersion": $ddts:spec-version ,
      (: removed totalItems here for "unstable" :)
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
    let $uri := local:id-to-uri($id)
    let $titles := dutil:get-titles($tei)

    let $filename := util:document-name($tei)
    let $paths := dutil:filepaths(base-uri($tei))
    let $playname := $paths?playname
    let $collection-name := util:collection-name($tei)
    let $corpusname := $paths?corpusname

    let $dublincore := local:play_metadata_to_dc($tei)

    let $dts-download := $ddts:api-base || "/corpora/" || $corpusname || "/plays/" || $playname || "/tei"
    
    (: This actually need to be URI templates, not URLs, but to implement this, 
    we need to know which params the endpoints are supporting 
    :)
    let $dts-document := $ddts:documents-base || "?resource=" || $uri || "{&amp;ref,start,end}" (: URI template:)
    let $dts-navigation := $ddts:navigation-base || "?resource=" || $uri || "{&amp;ref,start,end,down}" (: URI template:)
    let $dts-collection := $ddts:collections-base || "?id=" || $uri || "{&amp;nav}" (: URI template:)

    return
        map {
            "@id" : $uri ,
            "@type": "Resource" ,
            "title" : $titles?main ,
            "totalParents": 1 ,
            "totalChildren": 0 ,
            "dublinCore" : $dublincore ,
            "document" : $dts-document, 
            "navigation" : $dts-navigation,
            "collection" : $dts-collection ,
            "download": $dts-download
        }
};

(:~ 
: Metadata on a play in Dublin Core to be included with the response of the collection endpoint
: "dublinCore": {
      "@id": "dts:dublinCore",
      "@context": {
        "@vocab": "http://purl.org/dc/terms/"
      }
: this is the dublin core terms namespace
: Currently only literals are used, but probably a better rendering of metadata in rdf using dcterms is needed

:)
declare function local:play_metadata_to_dc($tei as element(tei:TEI))
as map() {

    let $titles := dutil:get-titles($tei)
    let $lang := $tei/@xml:lang/string()
    let $authors := dutil:get-authors($tei)
    let $creators := for $author in $authors return 
        $author?name

    return

    map {
            "language" : $lang,
            "creator" : $creators
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
as item()+
{
  
  (: Retrieve the TEI file:)
  let $tei := collection($config:corpora-root)/tei:TEI[@xml:id = $id]
    
  return
      if ( $tei/name() eq "TEI" ) then
        
        let $citationTrees := map { "citationTrees" : local:generate-citationTrees($tei) } return

            
            map:merge( 
                (map {"@context" : $ddts:dts-jsonld-context-url, "dtsVersion" : $ddts:spec-version } , 
                local:teidoc-to-collection-member($tei) 
                , $citationTrees ) )
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

 : this implements the "Parent Collection Query" as described in the specification of the collections endpoint
 : https://distributed-text-services.github.io/specifications/versions/1-alpha/#collection-endpoint
 :
 : @param $id Identifier of the document, e.g. "ger000278"
 
 :)
declare function local:child-readable-collection-with-parent-by-id($id as xs:string) 
as map()
{
    let $self := local:child-readable-collection-by-id($id)
    
    (: get parent collection and remove the members :)
    
    (: TODO: maybe use a dutil:function instead; this is very custom; not sure how this will
    work when something is changed in the general API code
     :)
    let $file-db-path := util:collection-name(collection($config:corpora-root)/tei:TEI[@xml:id eq $id])
    let $corpusname := tokenize(replace($file-db-path, "/db/dracor/corpora/",""),"/")[1] 
    
    (: get the parent by the function to generate a collection :)
    let $parent := local:corpus-to-collection($corpusname)
    
    (: remove "members" and "@context" :)
    let $parent-without-members := map:remove($parent,"member")
    let $parent-without-context := map:remove($parent-without-members, "@context")
    let $members := map {"member" : array { $parent-without-context }} 
    
    return
        map:merge(($self, $members))
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
    let $self-without-members := map:remove($self, "member")

    (: get the root collection and prepare :)
    let $parent := local:root-collection()
    (: remove the members :)
    let $parent-without-members := map:remove($parent, "member")
    (: remove "@context" :)
    let $prepared-parent := map:remove($parent-without-members, "@context")

    let $member := map { "member" : array { $prepared-parent } }

    (: merge the maps :)
    let $result := map:merge( ($self-without-members, $member) )

    return $result
};


(:~
 : Citation Trees
 :
 : Maybe at some point there will be multiple citation trees, but for now there is only one
 :
 : @param $tei TEI file (play)
:)
declare function local:generate-citationTrees($tei as element(tei:TEI)) 
as item()+ {
    (: returns the defaul citation tree as a sequence to be converted to an array:)
    array{
        local:generate-citationTree($tei,"default")
    }
};

(:~
 : Citation Trees
 :
 : Maybe at some point there will be multiple citation trees, but for now there is only one
 : 
 : @param $tei TEI file (play)
 : @param $type Type of the citation tree (only "default" is supported)

:)
declare function local:generate-citationTree($tei as element(tei:TEI), $type as xs:string)
as item() {
    if ( $type eq "default" ) then 
        let $citeStructure := local:generate-citeStructure($tei) return
        let $maxCiteDepth := local:get-citeDepth($tei)
        return
        map {
            "@type": "CitationTree",
            "maxCiteDepth" : $maxCiteDepth,
            "citeStructure" : $citeStructure
            }
    else ()
};



(:~
 :
 : Helper Function that generates dts:citeStructure to be included in the collection endpoint when requesting a resource
 : Deprecated, maybe; alpha-1 introduced citation trees!
 :
 : @param $tei TEI file
 :
 :)
declare function local:generate-citeStructure($tei as element(tei:TEI) )
as item() {
    (: Generate citeStructure to be used in citationTree :)

    let $set := if ($tei//tei:front/tei:set) then ("setting") else ()
    let $titlePage := if ($tei//tei:front/tei:titlePage) then ("title_page") else ()
    
    let $front-structure-types :=

        if ($tei//tei:front) then
            array {
                for $front-sub-structure-type in (distinct-values($tei//tei:front/tei:div/@type/string() ), $titlePage, $set)
                return
                    map{ 
                        "@type" : "CiteStructure",
                        "citeType": lower-case($front-sub-structure-type) }
            }
        else()

    let $front-structure := map { 
        "@type" : "CiteStructure",
        "citeType" : "front" , 
        "citeStructure" : $front-structure-types }

    let $body-structure :=
        (: structure body - act - scene :)
        (: this has speeches as well as stage directions :)
        if ($tei//tei:body/tei:div[@type eq "act"] and $tei//tei:body/tei:div/tei:div[@type eq "scene"][tei:stage and tei:sp]) then
            map { 
                "@type" : "CiteStructure", 
                "citeType" : "body" ,
                "citeStructure" : array{ 
                    map{ 
                        "@type" : "CiteStructure" , 
                        "citeType" : "act" , 
                        "citeStructure" : array { 
                            map {
                                "@type" : "CiteStructure" ,
                                "citeType" : "scene" ,
                                "citeStructure" : array {
                                    map {
                                        "@type" : "CiteStructure" ,
                                        "citeType" : "speech"
                                    },
                                    map {
                                        "@type" : "CiteStructure" ,
                                        "citeType" : "stage_direction"
                                    }
                                } 
                            
                            }  }  } }
                }
        (: structure: body – scene :)
        (: this has speeches as well as stage directions :)
        else if ( $tei//tei:body/tei:div[@type eq "scene"][tei:sp and tei:stage] ) then
            map { 
                "@type" : "CiteStructure",
                "citeType" : "body" ,
                "citeStructure" : array{ map{ 
                    "@type" : "CiteStructure",
                    "citeType" : "scene",
                    "citeStructure" : array {
                        map {
                            "@type" : "CiteStructure",
                            "citeType" : "speech"
                        },
                        map {
                            "@type" : "CiteStructure",
                            "citeType" : "stage_direction"
                        }
                    } 
                    } } }
        (: structure: body - act, no scene :)
        else if ( $tei//tei:body/tei:div[@type eq "act"] and not($tei//tei:body/tei:div/tei:div) ) then
            map { 
                "@type" : "CiteStructure",
                "citeType" : "body" ,
                "citeStructure" : array{ 
                    map{ 
                        "@type" : "CiteStructure" ,
                        "citeType" : "act"  } 
                    } }

        (: other types than scenes and acts ... :)
        else if ( $tei//tei:body/tei:div[@type]/tei:div[@type] ) then
            let $types-1 := distinct-values($tei//tei:body/tei:div/@type/string() )
            let $types-2 := distinct-values( $tei//tei:body/tei:div[@type]/tei:div/@type/string() )
            return
                (: structure, like act and scene, only with different type-values :)
                if ( (count($types-1) = 1) and (count($types-2) = 1) ) then
                    map { 
                        "@type" : "CiteStructure",
                        "citeType" : "body" ,
                        "citeStructure" : array{ 
                            map{ 
                                "@type" : "CiteStructure",
                                "citeType" : lower-case($types-1) , 
                                "citeStructure" : array { 
                                    map {
                                        "@type" : "CiteStructure" ,
                                        "citeType" : lower-case($types-2) }  }  } }
                }


                else ()


        (: structure: only body :)
        else if ( $tei//tei:body  and not($tei//tei:body/tei:div[@type eq "act"]) and not($tei//tei:body/tei:div[@type eq "scene"]) ) then
            map { "citeType" : "body" }
        else ()

    let $back-structure :=
        if ($tei//tei:back) then map{ "citeType": "back"} else ()

    let $cite-structure := array {$front-structure, $body-structure,  $back-structure}

    return $cite-structure
};


(:
 : --------------------
 : Document Endpoint
 : --------------------
 :
 : see https://distributed-text-services.github.io/specifications/versions/1-alpha/#document-endpoint
 : could be /api/dts/document 
 :
 : MUST return "application/tei+xml"
 : will implement only GET
 :
 : Params:
 : $resource(Required) Identifier for a document. Where possible this should be a URI)
 : $ref	Passage identifier (used together with resource; can’t be used with start and end)
 : $start (For range) Start of a range of passages (can’t be used with ref)
 : $end (For range) End of a range of passages (requires start and no ref)
 : $tree 
 : $mediaType
 :
 : Params used in POST, PUT, DELETE requests are not availiable

 :)

(:~
 : DTS Document Endpoint
 :
 : Get a document according to the specification: https://distributed-text-services.github.io/specifications/versions/1-alpha/#document-endpoint
 :
 : @param $resource Identifier for a document
 : @param $ref Passage identifier (used together with id; can’t be used with start and end)
 : @param $start (For range) Start of a range of passages (can’t be used with ref)
 : @param $end (For range) End of a range of passages (requires start and no ref)
 : @param $tree
 : @param $mediaType
 :
 : @result TEI
 :)
declare
  %rest:GET
  %rest:path("/v1/dts/document")
  %rest:query-param("resource", "{$resource}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("tree", "{$tree}")
  %rest:query-param("mediaType", "{$media-type}")
  %rest:produces("application/tei+xml")
  %output:media-type("application/xml")
  %output:method("xml")
function ddts:document($resource, $ref, $start, $end, $tree, $media-type) {
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
    else if ( $media-type ) then
        (: requesting other format than TEI is not implemented :)
        (: This param is DEPRECATED in 1-alpha. Should be removed. Maybe mediaType will be added here :)
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
        (: need to check here if "short ID"/playname or full URI :)
        let $tei :=
            if ( matches($resource, concat("^", $ddts:base-uri, "/id/","[a-z]+[0-9]{6}$" ) ) ) then 
                collection($config:corpora-root)/tei:TEI[@xml:id = local:uri-to-id($resource)]
            else 
                collection($config:corpora-root)/tei:TEI[@xml:id = $resource]

        return
            (: check, if document exists! :)
            if ( $tei/name() eq "TEI" ) then
                (: here are valid requests handled :)

                if ( $ref ) then
                    (: requested a fragment :)
                    local:get-fragment-of-doc($tei, $ref)


                else if ( $start and $end ) then
                    (: requested a range; could be implemented, but not sure, if I will manage in time – at the Hackathon then :)
                    local:get-fragment-range($tei, $start, $end)

                else
                (: requested full document :)
                    local:get-full-doc($tei)

            else
                (: this might be DEPRECATED!! :)
                if ( not($resource) or $resource eq "" ) then
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
            <description>Document with the id '{$resource}' does not exist!</description>
        </error>
        )

};


(:~ 
:
: Get a range of fragments from start to end
: EXPERIMENTAL: This currently works only for segments on the same level that are part of a overarching structure, e.g. 
: scene 2 to scene 4 of the second act. It is not possible to query the segments across the boundaries of an act
:
:)
declare function local:get-fragment-range($tei as element(tei:TEI), $start as xs:string, $end as xs:string) {

    let $id := $tei/@xml:id/string()
    let $uri := local:id-to-uri($id)

    let $links := '<' || $ddts:collections-base  ||'?id=' || $uri || '>; rel="collection"'
    (: 1-alpha suggests that the Content-Type SHOULD be application/tei+xml . This could be implemented, but at least Chrome downloads the file and does not 
                display it if this content header is set; therefore it is not included at the moment :)

    (: let $link-header :=  (<http:header name='Link' value='{$links}'/>,  <http:header name='Content-Type' value='application/tei+xml'/>) :)
    let $link-header :=  <http:header name='Link' value='{$links}'/>
    

    (: A solution to getting the range of fragments on the same level, e.g. the first two acts, the 3rd to the 6th scene of the fourth act..
    would be to retrieve two sets of nodes and then subtracting the latter from the first (OK, have to subtract everything that is coming after the end)
     :)

    (: node set one:)
    (: this include the range and everything following after :)
    (: should not work for front, body, back on level one:)
    let $start_set :=
            (: structures on level 2 :)

            (: front structures level 2 :)
            (: div:)
            if ( matches($start, '^front.div.\d+$') ) then
                let $pos := xs:integer(tokenize($start,'\.')[last()])
                return
                ($tei//tei:front/tei:div[$pos], $tei//tei:front/tei:div[$pos]/following-sibling::node())
            (: xPath-ish 
            : tested with http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000001&start=front/div[1]&end=front/div[2]
            :)
            else if ( matches($start, 'front/div\[\d+\]$')) then
                let $pos := xs:int(replace(replace($start, "front/div\[",""),"\]",""))
                return 
                    ($tei//tei:front/tei:div[$pos], $tei//tei:front/tei:div[$pos]/following-sibling::node())
            (: tei:set in tei:front :)
            else if ( matches($start, '^front.set.\d+$') ) then
                let $pos := xs:integer(tokenize($start,'\.')[last()])
                return
                    ( $tei//tei:front/tei:set[$pos], $tei//tei:front/tei:set[$pos]/following-sibling::node() )
            (: TODO: implement xPath-ish ref here :)
            (: tei:castList in tei:front :)
            else if ( matches($start, '^front.castList.\d+$') ) then
                let $pos := xs:integer(tokenize($start,'\.')[last()])
                return
                    ( $tei//tei:front/tei:castList[$pos], $tei//tei:front/tei:castList[$pos]/following-sibling::node() )
            (: TODO: implement xPath-ish ref here :)

            (: body structures level 2 :)
            else if ( matches($start, "^body.div.\d+$") ) then
                let $pos := xs:integer(tokenize($start,'\.')[last()])
                return
                    ( $tei//tei:body/tei:div[$pos] , $tei//tei:body/tei:div[$pos]/following-sibling::node() )
            (: xPath-ish :)
            (:tested with http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000001&start=body/div[1]&end=body/div[2]:)
            else if ( matches($start, "^body/div\[\d+\]$") ) then
                let $pos := xs:integer(replace(replace($start,"body/div\[",""),"\]",""))
                return 
                    ( $tei//tei:body/tei:div[$pos] , $tei//tei:body/tei:div[$pos]/following-sibling::node() )

            (: back structures level 2 :)
            else if ( matches($start, "^back.div.\d+$") ) then
                let $pos := xs:integer(tokenize($start,'\.')[last()])
                return
                    ( $tei//tei:back/tei:div[$pos], $tei//tei:back/tei:div[$pos]/following-sibling::node()) 

            (: structures on level 3:)
            else if ( matches($start, "^body.div.\d+.div.\d+$") ) then
                let $div1-pos := xs:integer(tokenize($start, "\.")[3])
                let $div2-pos := xs:integer(tokenize($start, "\.")[last()])
                return
                    ( $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos] , $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/following-sibling::node() )

            (: xPath-ish:)
            (: tested with http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000001&start=body/div[1]/div[1]&end=body/div[1]/div[2] :)
            else if ( matches($start, "^body/div\[\d+\]/div\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($start,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($start, "/")[3], "div\[",""),"\]",""))
                return
                    ( $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos] , $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/following-sibling::node() )
            
            (: sp on level 3 – xpath-ish :)
            (: body/div[x]/sp[x] :)
            (: added this, need to debug :)
            else if ( matches($start, "^body/div\[\d+\]/sp\[\d+\]$") ) then
                let $div-pos := xs:int(replace(replace(tokenize($start,"/")[2],"div\[",""),"\]",""))
                let $sp-pos := xs:int(replace(replace(tokenize($start, "/")[3], "sp\[",""),"\]",""))
                return
                    ( $tei//tei:body/tei:div[$div-pos]/tei:sp[$sp-pos] , $tei//tei:body/tei:div[$div-pos]/tei:sp[$sp-pos]/following-sibling::node() )
            
            (: stage on level 3 - xpath-ish :)
            (: body/div[x]/stage[y] :)
            else if ( matches($start, "^body/div\[\d+\]/stage\[\d+\]$") ) then
                let $div-pos := xs:int(replace(replace(tokenize($start,"/")[2],"div\[",""),"\]",""))
                let $stage-pos := xs:int(replace(replace(tokenize($start, "/")[3], "stage\[",""),"\]",""))
                return
                    ( $tei//tei:body/tei:div[$div-pos]/tei:stage[$stage-pos] , $tei//tei:body/tei:div[$div-pos]/tei:stage[$stage-pos]/following-sibling::node() )
            

            (: structures on level 4 :)
            (: body/act/scene/sp|stage :)
            (: only xPath-ish ref values are supported here :)
            else if ( matches($start, "^body/div\[\d+\]/div\[\d+\]/sp\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($start,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($start, "/")[3], "div\[",""),"\]",""))
                let $sp-pos := xs:int(replace(replace(tokenize($start, "/")[last()],"sp\[",""),"\]","")) 
                return
                    ( $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:sp[$sp-pos] , $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:sp[$sp-pos]/following-sibling::node() )

            (: stage on level 4 :)
            (: tested with http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000001&start=body/div[1]/div[2]/stage[1]&end=body/div[1]/div[2]/sp[1]:)
            else if ( matches($start, "^body/div\[\d+\]/div\[\d+\]/stage\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($start,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($start, "/")[3], "div\[",""),"\]",""))
                let $stage-pos := xs:int(replace(replace(tokenize($start, "/")[last()],"stage\[",""),"\]","")) 
                return
                    ( $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:stage[$stage-pos] , $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:stage[$stage-pos]/following-sibling::node() )

            (: front :)
            else if ( matches($start, "^front$") ) then ( $tei//tei:front, $tei//tei:front/following-sibling::node() )

            (: body :)
            else if ( matches($start, "^body$") ) then ( $tei//tei:body, $tei//tei:body/following-sibling::node() )

            (: back :)
            else if ( matches($start, "^back$") ) then ( $tei//tei:back, $tei//tei:back/following-sibling::node() )

            (: not matched by any rule :)
            else ()


    (:  node set two :)
    (: all sibling nodes following the end node :)
    let $end_set :=
            (: structures on level 2 :)

            (: front structures level 2 :)
            (: div:)
            if ( matches($end, '^front.div.\d+$') ) then
                let $pos := xs:integer(tokenize($end,'\.')[last()])
                return
                $tei//tei:front/tei:div[$pos]/following-sibling::node()
            (: xPath-ish :)
            else if ( matches($end, 'front/div\[\d+\]$')) then
                let $pos := xs:int(replace(replace($end, "front/div\[",""),"\]",""))
                return 
                    $tei//tei:front/tei:div[$pos]/following-sibling::node()
            (: tei:set in tei:front :)
            else if ( matches($end, '^front.set.\d+$') ) then
                let $pos := xs:integer(tokenize($end,'\.')[last()])
                return
                    $tei//tei:front/tei:set[$pos]/following-sibling::node()
            (: tei:castList in tei:front :)
            else if ( matches($end, '^front.castList.\d+$') ) then
                let $pos := xs:integer(tokenize($end,'\.')[last()])
                return
                    $tei//tei:front/tei:castList[$pos]/following-sibling::node() 

            (: body structures level 2 :)
            else if ( matches($end, "^body.div.\d+$") ) then
                let $pos := xs:integer(tokenize($end,'\.')[last()])
                return
                    $tei//tei:body/tei:div[$pos]/following-sibling::node() 
            (:xPath-ish :)
            else if ( matches($end, "^body/div\[\d+\]$") ) then
                let $pos := xs:integer(replace(replace($end,"body/div\[",""),"\]",""))
                return 
                    $tei//tei:body/tei:div[$pos]/following-sibling::node() 

            (: back structures level 2 :)
            else if ( matches($end, "^back.div.\d+$") ) then
                let $pos := xs:integer(tokenize($end,'\.')[last()])
                return
                     $tei//tei:back/tei:div[$pos]/following-sibling::node()

            (: structures on level 3:)
            else if ( matches($end, "body.div.\d+.div.\d+$") ) then
                let $div1-pos := xs:integer(tokenize($end, "\.")[3])
                let $div2-pos := xs:integer(tokenize($end, "\.")[last()])
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/following-sibling::node() 

            (: xPath-ish:)
            else if ( matches($end, "^body/div\[\d+\]/div\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($end,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($end, "/")[3], "div\[",""),"\]",""))
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/following-sibling::node() 
            
            (: level3: sp in div :)
            else if ( matches($end, "^body/div\[\d+\]/sp\[\d+\]$") ) then
                let $div-pos := xs:int(replace(replace(tokenize($end,"/")[2],"div\[",""),"\]",""))
                let $sp-pos := xs:int(replace(replace(tokenize($end, "/")[3], "sp\[",""),"\]",""))
                return
                    $tei//tei:body/tei:div[$div-pos]/tei:sp[$sp-pos]/following-sibling::node() 

            (: stage on level 3 - xpath-ish :)
            (: body/div[x]/stage[y] :)
            else if ( matches($end, "^body/div\[\d+\]/stage\[\d+\]$") ) then
                let $div-pos := xs:int(replace(replace(tokenize($end,"/")[2],"div\[",""),"\]",""))
                let $stage-pos := xs:int(replace(replace(tokenize($end, "/")[3], "stage\[",""),"\]",""))
                return
                    $tei//tei:body/tei:div[$div-pos]/tei:stage[$stage-pos]/following-sibling::node()


            (: level4 structures :)
            (: sp on level 4 :)
            else if ( matches($end, "^body/div\[\d+\]/div\[\d+\]/sp\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($end,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($end, "/")[3], "div\[",""),"\]",""))
                let $sp-pos := xs:int(replace(replace(tokenize($end, "/")[last()],"sp\[",""),"\]","")) 
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:sp[$sp-pos]/following-sibling::node() 

            (: stage on level 4 :)
            else if ( matches($end, "^body/div\[\d+\]/div\[\d+\]/stage\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($end,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($end, "/")[3], "div\[",""),"\]",""))
                let $stage-pos := xs:int(replace(replace(tokenize($end, "/")[last()],"stage\[",""),"\]","")) 
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:stage[$stage-pos]/following-sibling::node()

            (: front :)
            else if ( matches($end, "^front$") ) then $tei//tei:front/following-sibling::node() 

            (: body :)
            else if ( matches($end, "^body$") ) then  $tei//tei:body/following-sibling::node() 

            (: back :)
            else if ( matches($end, "^back$") ) then  $tei//tei:back/following-sibling::node() 


            (: not matched by any rule :)
            else()

    (: retrieving a fragment should go into a separate function :)
    
    let $fragment := $start_set except $end_set
    

    return
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

(: The URI template, that would be the self description of the endpoint – unclear, how this should be implemented :)
(: should include a link to a machine readable documentation :)
(: Probably, this is DEPRECATED in 1-alpha! :)
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
    let $uri := local:id-to-uri($id)
    (: requested complete document, just return the TEI File:)
                (: must include the link header as well :)
                (: The link header is smaller since the 1-alpha :)
                (: It is now not required but SHOULD :)
                (: "Link SHOULD contain a URI that links back to the Collection endpoint for the requested Resource, e.g. as Link: </dts/api/collection/?id=https://en.wikisource.org/wiki/Dracula; rel="collection"  :)
                (: see https://datatracker.ietf.org/doc/html/rfc5988 :)
                
                (: pre-alpha was: :)
                (: let $links := '<' || $ddts:navigation-base || '?id=' || $id || '>; rel="contents", <' || $ddts:collections-base  ||'?id=' || $id || '>; rel="collection"' :)
                (: 1-alpha only contains link to the collection endpoint :)
                let $links := '<' || $ddts:collections-base  ||'?id=' || $uri || '>; rel="collection"'

                (: 1-alpha suggests that the Content-Type SHOULD be application/tei+xml . This could be implemented, but at least Chrome downloads the file and does not 
                display it if this content header is set; therefore it is not included at the moment :)

                (: let $link-header :=  (<http:header name='Link' value='{$links}'/>,  <http:header name='Content-Type' value='application/tei+xml'/>) :)
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
 : Return a document fragment via the document endpoint
 :
 : @param $tei TEI of the Document
 : @param $ref identifier of the fragment requested
 : :)
declare function local:get-fragment-of-doc($tei as element(tei:TEI), $ref as xs:string) {
    let $id := $tei/@xml:id/string()
    let $uri := local:id-to-uri($id)

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
            (: xPath-ish syntax of the ID :)
            else if ( matches($ref, '^front/div\[\d+\]$') ) then
                (: let $pos := xs:int(replace(replace(replace(tokenize($ref,'/')[last()],"\[",""),"\]",""),"div","")) :)
                (: little bit more readable, but still... :)
                let $pos := xs:int(replace(replace($ref, "front/div\[",""),"\]",""))
                return $tei//tei:front/tei:div[$pos]
            (: tei:set in tei:front :)
            else if ( matches($ref, '^front.set.\d+$') ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                    $tei//tei:front/tei:set[$pos]
            (: xpath-ish :)
            else if ( matches($ref, '^front/set\[\d+\]$') ) then
                let $pos := xs:int(replace(replace($ref, "front/set\[",""),"\]",""))
                return
                    $tei//tei:front/tei:set[$pos]
            (: tei:castList in tei:front :)
            (: not sure if this is implemented; also depends on the encoding :)
            else if ( matches($ref, '^front.castList.\d+$') ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                    $tei//tei:front/tei:castList[$pos]
            else if ( matches($ref, '^front/castList\[\d+\]$') ) then
                let $pos := xs:int(replace(replace($ref, "front/castList\[",""),"\]",""))
                return
                    $tei//tei:front/tei:castList[$pos]

            (: tei:titlePage in tei:front:)
            (: this is only xPath-ish :)
            else if ( matches($ref, '^front/titlePage\[\d+\]$') ) then
                let $pos := xs:int(replace(replace($ref, "front/titlePage\[",""),"\]",""))
                return
                    $tei//tei:front/tei:titlePage[$pos]


            (: body structures level 2 :)
            else if ( matches($ref, "^body.div.\d+$") ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                    $tei//tei:body/tei:div[$pos]
            (: xPath-ish :)
            else if ( matches($ref, "^body/div\[\d+\]$") ) then
                let $pos := xs:integer(replace(replace($ref,"body/div\[",""),"\]",""))
                return $tei//tei:body/tei:div[$pos]
            
            (: there are also cases in which we have a stage direction in body, without a div :)
            (: TODO: implement, e.g. http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000638&ref=body/stage[1] :)

            (: back structures level 2 :)
            else if ( matches($ref, "^back.div.\d+$") ) then
                let $pos := xs:integer(tokenize($ref,'\.')[last()])
                return
                    $tei//tei:back/tei:div[$pos]
            (: xPath-ish :)
            else if ( matches($ref, '^back/div\[\d+\]$') ) then
                let $pos := xs:int(replace(replace($ref, "back/div\[",""),"\]",""))
                return $tei//tei:back/tei:div[$pos]

            (: structures on level 3:)
            (: TODO: xPath-ish implement! :)
            else if ( matches($ref, "^body.div.\d+.div.\d+$") ) then
                let $div1-pos := xs:integer(tokenize($ref, "\.")[3])
                let $div2-pos := xs:integer(tokenize($ref, "\.")[last()])
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]
            
            else if ( matches($ref, "^body/div\[\d+\]/div\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($ref,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($ref, "/")[last()], "div\[",""),"\]",""))
                return 
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]
            
            (: there could also be speeches and stage direction :)
            (: this needs to be tested! Works with http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000003&ref=body/div[1]/sp[1]:)
            (: sp right inside the first div :)
            else if ( matches($ref, "^body/div\[\d+\]/sp\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($ref,"/")[2],"div\[",""),"\]",""))
                let $sp-pos := xs:int(replace(replace(tokenize($ref, "/")[last()],"sp\[",""),"\]",""))
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:sp[$sp-pos]
            (: stage right inside the first div :)
            else if ( matches($ref, "^body/div\[\d+\]/stage\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($ref,"/")[2],"div\[",""),"\]",""))
                let $stage-pos := xs:int(replace(replace(tokenize($ref, "/")[last()],"stage\[",""),"\]",""))
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:stage[$stage-pos]


            (: structures on level 4 :)
            (: for these the dot-notation is not available :)
            (: speeches on act/scene/ :)
            (: this is currently not supported by the navigation endpoint:)
            else if ( matches($ref, "body/div\[\d+\]/div\[\d+\]/sp\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($ref,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($ref, "/")[3], "div\[",""),"\]",""))
                let $sp-pos := xs:int(replace(replace(tokenize($ref, "/")[last()],"sp\[",""),"\]",""))
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:sp[$sp-pos]
            (: stage directions in act/scene :)
            else if ( matches($ref, "body/div\[\d+\]/div\[\d+\]/stage\[\d+\]$") ) then
                let $div1-pos := xs:int(replace(replace(tokenize($ref,"/")[2],"div\[",""),"\]",""))
                let $div2-pos := xs:int(replace(replace(tokenize($ref, "/")[3], "div\[",""),"\]",""))
                let $stage-pos := xs:int(replace(replace(tokenize($ref, "/")[last()],"stage\[",""),"\]",""))
                return
                    $tei//tei:body/tei:div[$div1-pos]/tei:div[$div2-pos]/tei:stage[$stage-pos]



            (: not matched by any rule :)
            else()

    (: The Link header in pre-alpha contained more links, in 1-alpha it is only a link to the collection endpoint:)
    (: pre-alpha used a dedicated function, which is deprecated now :)
    (: let $link-header := local:link-header-of-fragment($tei,$ref) :)
    (: 1-alpha use the same code as in the function that returns the whole doc:)
    
    let $links := '<' || $ddts:collections-base  ||'?id=' || $uri || '>; rel="collection"'
    (: 1-alpha suggests that the Content-Type SHOULD be application/tei+xml . This could be implemented, but at least Chrome downloads the file and does not 
                display it if this content header is set; therefore it is not included at the moment :)

    (: let $link-header :=  (<http:header name='Link' value='{$links}'/>,  <http:header name='Content-Type' value='application/tei+xml'/>) :)
    let $link-header :=  <http:header name='Link' value='{$links}'/>
    
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
 : DEPRECATED!! Reason: 1-alpha only includes a link to the collection (and the Content-Type)

 : Pre-alpha: Generates the Link Header needed for the response of the Document endpoint when requesting a fragment
 : @param $tei TEI Document (full doc)
 : @param $ref Identifier of the fragment
 :
 : :)
declare function local:link-header-of-fragment($tei as element(tei:TEI), $ref as xs:string) {
    (: This function is DEPRECATED. I keep it here in case a later version of the DTS adds the
    other links again :)

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
 : @param $start ... todo: add from spec
 : @param $end ... todo: add from spec
 : @param $level DEPRECATED
 : @param $down
 :
 : @result JSON Object
 :)
 declare
  %rest:GET
  %rest:path("/v1/dts/navigation")
  %rest:query-param("resource", "{$resource}")
  %rest:query-param("ref", "{$ref}")
  %rest:query-param("start", "{$start}")
  %rest:query-param("end", "{$end}")
  %rest:query-param("level", "{$level}")
  %rest:query-param("down", "{$down}")
  %rest:produces("application/ld+json")
  %output:media-type("application/ld+json")
  %output:method("json")
 function ddts:navigation($resource, $ref, $start, $end, $level, $down) {
    (: parameter $id is mandatory :)
    if ( not($resource) ) then
        (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        "Mandatory parameter 'resource' is missing."
        )
    (: both ref and either start or end is specified should return an error :)
    else if ( $ref and ($start or $end) ) then
        (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        "Bad Request: Use of both parameters 'ref' and 'start' or 'end' is not allowed."
        )
    (: should not use start without end or vice versa :)
    else if ( ($start and not($end)) or ($end and not($start)) ) then 
        (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        "Bad Request: Must provide both parameters 'start' and 'end'."
        )
    (: down=absent, ref=absent, start/end=absent --> 400 Bad Request Error :)
    else if ( not($down) and not($ref) and ( not($start) and not($end) ) ) then 
        (
        <rest:response>
            <http:response status="400"/>
        </rest:response>,
        "Bad Request: Must provide at least one of the parameters 'down','ref' or both 'start' and 'end'. E.g. use parameter 'down=1' to retrieve the top-level citationStructures of this resource."
        )
    else
        (: check, if there is a resource with this identifier :)
        let $tei := if ( matches($resource, concat("^", $ddts:base-uri, "/id/","[a-z]+[0-9]{6}$" ) ) ) then
            collection($config:corpora-root)/tei:TEI[@xml:id = local:uri-to-id($resource)]
        else
            collection($config:corpora-root)/tei:TEI[@xml:id = $resource]

        return
            (: check, if document exists! :)
            if ( $tei/name() eq "TEI" ) then
                (: here are valid requests handled :)

                (: down = absent ref= present start/end = absent --> Information about the CitableUnit identified by ref. No member property in the Navigation object. :)
                if ( not($down) and ( not($start) and not($end) ) and $ref ) then
                    (: what happens if ref is not valid? must not return 500! :)
                    
                    if ( local:validate-ref($ref, $tei) eq true() ) then
                        local:citeable-unit-by-ref($tei, $ref)
                    else 
                        (
                        <rest:response>
                            <http:response status="404"/>
                        </rest:response>,
                        "Not found: The identifier provided as parameter 'ref' does not match a citeable unit."
                        )
                

                (: down = absent ref = absent start/end = present --> Information about the CitableUnits identified by start and by end. No member property in the Navigation object. :)
                else if ( not($down) and not($ref) and ($start and $end) ) then 
                    (: check if start and end are valid:)
                    if ( local:validate-ref($start, $tei) eq true() and local:validate-ref($end, $tei) eq true()  ) then
                        (: when requesting structures deeper down we expect that start and end have the same parent
                        i.e. it is not implemented to get the last two scenes of the first act and the first scene of the second act
                        Don't know if the specification would allow for that but it would have to be implemented in a different way than it is currently :)
                        if ( local:start_end_share_same_parent($start, $end, $tei) eq true() ) then
                            local:citeable-units-by-start-end($tei, $start, $end)
                        else 
                            (
                        <rest:response>
                            <http:response status="501"/>
                        </rest:response>,
                        "Not implemented: It is not possible to get a range if the citeable units identified by start and and do not share the same parent."
                        )
                    else 
                        (
                        <rest:response>
                            <http:response status="404"/>
                        </rest:response>,
                        "Not found: The identifier(s) provided as parameter 'start' and/or 'end' do not match a citeable unit."
                        )                

                (: down=0	ref=present	start/end=absent -->	Information about the CitableUnit identified by ref along with a member property that is an array of CitableUnits that are siblings (sharing the same parent) including the current CitableUnit identified by ref. :)
                else if ( $down eq "0" and $ref and not($start) and not($end)) then
                
                    if ( local:validate-ref($ref, $tei) eq true() ) then
                        local:siblings-of-citeable-unit-by-ref($tei, $ref)
                    else 
                        (
                        <rest:response>
                            <http:response status="404"/>
                        </rest:response>,
                        "Not found: The identifier provided as parameter 'ref' does not match a citeable unit."
                        )
                
                (: Level 1 :)
                (: Parameter level is deprecated; use param "down" insted 
                This level is either identified by having no down param or param down equals 1
                :)
                else if ( not($ref) and not($start) and ($down eq "1") ) then
                    (: this function has been adapted to 1-alpha :)
                    local:navigation-level1($tei)

                (: in 1-alpha there are some combinations of the parameters we need to check
                : see https://distributed-text-services.github.io/specifications/versions/1-alpha/#uri-for-navigation-endpoint-requests
                :)

                (: down=absent, ref=absent, start/end=absent --> 400 Bad Request Error :)
                (: any other value of down than  1 :)    
                
                else if (not($ref) and not($start) and ($down eq "2") ) then
                    (:
                    First run of the DTS-Validation raised an error here:

                    tests/test_navigation_endpoint.py::test_navigation_two_down_response_validity
request URI: https://dev.dracor.org/api/v1/dts/navigation?resource=https://dev.dracor.org/id/test000001&down=2
Reason: the API raises an error here (I understand this wasn't implemented fully yet). The expected behaviour is the following: retrieve a citation sub-tree containing children + grand-children; the corresponding Citable Units should be contained in the member property of the returned Navigation response object.
                     :)
                    
                (: Level 2 :)
                local:navigation-level2($tei)


                else if (not($ref) and not($start) and ($down eq "3") ) then
                    local:navigation-level3($tei) 
               
                else if (not($ref) and not($start) and ($down eq "4") ) then
                    local:navigation-level4($tei) 
                
                else if (not($ref) and not($start) and ($down eq "-1") ) then
                    local:navigation-whole-citeTree($tei)


                (: Some in the case of tei:front, would contain the divisions tei:div of tei:front, which is also the tei:castList :)
                (: in the case of tei:body, it would be the top-level divisions of the body, normally "acts" – could also be "scenes" if there are no "acts"... but this case must be handled separately :)
                else if ( $level and not($ref) ) then
                    (: The following function is DEPRECATED; had to re-write most of it for 1-alpha :)
                    (: local:navigation-level-n($tei, $level) :)
                    (: Will return an error if someone uses this deprecated behaviour :)
                    (
                        <rest:response>
                            <http:response status="400"/>
                        </rest:response>,
                    "The parameter 'level' is deprecated in version 1-alpha. This functionality is not supported anymore."
                    )


                (: Level 3 :)
                (: don't care about tei:front here, but in the case of a drama with acts and scenes in the tei:body, this would normally list the "scenes" :)

                (: Level 4 :)
                (: in the boilerplate play front/body - acts - scenes, this would return the structural divisions like speeches and stage directions :)

                (: we will have to see, if this will work out like this; I might implement it for this case and return only level zero, e.g. the whole document, if it doesn't fit this pattern :)
                (: special case, that is implemented: ref is a level 1 division of body, e.g. an act, will return the scenes of this act. :)
                (: need to test for invalid values of parameter down; until level 5 (which will be never reached) all possible values are checked :)
                else if ( $down and not(
                    $down eq "-1" or
                    $down eq "0" or 
                    $down eq "1" or 
                    $down eq "2" or 
                    $down eq "3" or 
                    $down eq "4" or
                    $down eq "5" ) ) then
                    (
                        <rest:response>
                            <http:response status="400"/>
                        </rest:response>,
                    "Bad Request: The value of parameter 'down' is not supported. Try a value between -1 and 4."
                    )
                else if ( $ref and $down ) then

                    (: should check if requesting the layer makes sense :)
                    (: This check also works if there is no Citeable Unit identified by ref, e.g. if 
                    the cite depth provided as down does not make any sense inside the whole TEI Document, it is 
                    not important if the value of the parameter ref is actually valid; 
                    need only to check for valid ref if the value of down makes sense
                    :)
                    let $max-cite-depth := local:get-citeDepth($tei)
                    let $level-of-fragment-identified-by-ref := local:get-level-from-ref($ref)
                    return
                        if ( (xs:int($down) + $level-of-fragment-identified-by-ref) > $max-cite-depth ) then
                        (: could not go that deep, $down exceeds max depth of the citation tree :)
                        (
                        <rest:response>
                            <http:response status="400"/>
                        </rest:response>,
                        "Bad Request: The value of parameter 'down' " || $down || " is too high. Maximum allowed is " || xs:string($max-cite-depth - $level-of-fragment-identified-by-ref)
                        )

                        else 
                            (:could check here if the functionality is already available:)
                            (: TODO: implement this for other structures as body as well :)
                            if (starts-with($ref,"body")) then
                                (: a problem could still be that the value of ref is not valid, check for this as well :)
                                if ( local:validate-ref($ref, $tei) eq true() ) then
                                    local:descendants-of-subdivision($tei, $ref, $down)
                                else 
                                    (
                                    <rest:response>
                                        <http:response status="404"/>
                                    </rest:response>,
                                    "Not found: The identifier provided as parameter 'ref' does not match a citeable unit."
                                    )
                            (: the following block is experimental. See how I can get sub-divisions of front with, e.g. $down=1 as well :)
                            else if (starts-with($ref, "front")) then
                                (: validity of $ref is checked :)
                                if ( local:validate-ref($ref, $tei) eq true() ) then
                                    local:descendants-of-subdivision($tei, $ref, $down)
                                else 
                                    (
                                     
                                    <rest:response>
                                        <http:response status="404"/>
                                    </rest:response>,
                                    "Not found: The identifier provided as parameter 'ref' does not match a citeable unit."
                                    
                                    )  
                            else
                                (
                        <rest:response>
                            <http:response status="501"/>
                        </rest:response>,
                        "Not implemented: This functionality is currently only available for the text proper, i.e. ref values starting with 'body'."
                        )



                (: there is also a conflicting hierarchy, e.g. Pages! which would be a second cite structure :)


                (: valid requests end above :)

                (: don't really know, when this could become true :)
                
                else if ($start and $end and $down) then
                    (: "start and end AND (!) down" :)
                    (: not everything can be implemented; I need to check here if the request is supported :)
                     if ( local:validate-ref($start, $tei) eq true() and local:validate-ref($end, $tei) eq true()  ) then
                        (: it is already checked if the value of down makes sense:)
                        (: TODO: here this probably does not work for all structures, need to check :) 
                        if ($down eq "1") then
                            local:citeable-units-by-start-end-with-members-down-1($tei, $start, $end, $down)
                        else if ($down eq "2") then
                            (: TODO:need to check if it is possible to go down; use maxCiteDepth; won't fix for now:)
                            (: http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000171&start=body/div[2]&end=body/div[4]&down=2 :)
                            local:citeable-units-by-start-end-with-members-down-2($tei, $start, $end, $down)
                        else if ($down eq "3") then
                            (: this only make sense for a strange range of front to body and then three down, e.g.
                            http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000171&start=front&end=body&down=3 :)
                            local:citeable-units-by-start-end-with-members-down-3($tei, $start, $end, $down)
                        
                        else if ($down eq "-1") then  
                            (: the whole cite tree of the range :)
                            local:navigation-range-whole-citeTree($tei, $start, $end)
                        else
                            (
                        <rest:response>
                            <http:response status="501"/>
                        </rest:response>,
                        "Requesting children of members of the range with the used value of down '" || $down || "' is not implemented."
                        )
                    else 
                        (
                        <rest:response>
                            <http:response status="404"/>
                        </rest:response>,
                        "Not found: The identifier(s) provided as parameter 'start' and/or 'end' do not match a citeable unit."
                        )
                
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
                "Document with the id '" ||  $resource || "' does not exist."
                )
 };

(:~
: Check if the value of the parameter 'ref' can be used to retrieve a CiteableUnit from the TEI-XML file 
: supplied as $tei
:)
declare function local:validate-ref($ref as xs:string, $tei as element(tei:TEI)) {
    (:http://localhost:8080/exist/restxq/v1/dts/navigation?resource=ger000569&ref=body/div[1]:)
    (: this is not the best ever regex, but it at least prevents that there are some strange xpath functions included
    that could possibly introduce a security risk
    It is not said, that the $ref value will already be a valid identifier in the context of the TEI file
     :)
    if ( matches($ref, "^(body|front|back)(/(div|stage|sp|set|castList)\[\d+\])*?$") ) then 
        (: now check if there is a segment/CiteableUnit that can be identified with such an identifier :)
        let $tei-fragment :=  util:eval("$tei/tei:text/tei:" || replace($ref, "/", "/tei:")) 
        return 
            (:we expect that the identifier matches a xml element. If it is not an XML element, then ref is not valid:)
            if ( $tei-fragment instance of element() ) then true()
            else false()
    else
        (: does not match the regex; maybe also evaluate if the regex is really suiteable if frequent problems are reported:)
        false()
};


 (:~
 : Navigate a resource on level 1
 : TODO: refactor this to use local:navigation-basic-response and just add the member field
 :)
 declare function local:navigation-level1($tei as element(tei:TEI)) {

     let $doc-id := $tei/@xml:id/string()
     let $doc-uri := local:id-to-uri($doc-id)
     (:Will add down parameter here:)
     let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;down=1"
     
     let $basic-response-map := local:navigation-basic-response($tei, $request-id, "", "", "") (: use the default uri templates:)

    (: when requesting the resource include the level 1 divisions, e.g. front, body, back as members :)
    let $member :=
        (
        if ($tei//tei:front) then local:citable-unit("front", 1, (), "front", $tei//tei:front, $doc-uri ) else () ,
        if ($tei//tei:body) then local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri ) else (),
        if ($tei//tei:back) then local:citable-unit("back", 1, (), "back", $tei//tei:back, $doc-uri ) else ()
        )

     return
    map:merge( ($basic-response-map, map{"member" : $member}) )
     
 };

 (:~ 
 : Navigate a resource on level 2
 : There is a test in the DTS-Validator that tests for level 2.
 :
 : tests/test_navigation_endpoint.py::test_navigation_two_down_response_validity
 : request URI: https://dev.dracor.org/api/v1/dts/navigation?resource=https://dev.dracor.org/id/test000001&down=2
 : 
 : The expected behaviour is the following: retrieve a citation sub-tree containing children + grand-children; 
 : the corresponding Citable Units should be contained in the member property of the returned Navigation response object.
 :)
declare function local:navigation-level2($tei as element(tei:TEI)) {

    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)
     
    (:Will add down parameter here:)
    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;down=2"
     
    let $basic-response-map := local:navigation-basic-response($tei, $request-id, "", "", "") (: use the default uri templates:)

    (: when requesting the resource include the level 1 divisions, e.g. front, body, back as members :)
    
    let $member :=
        (
            (: include front = level 1 then followed by all children of front :)
        if ($tei//tei:front) then ( 
            local:citable-unit("front", 1, (), "front", $tei//tei:front, $doc-uri ) ,
            local:members-down-1($tei//tei:front, "front", 1, $doc-uri)) 
            else () ,

        (: include body and its children :)
        if ($tei//tei:body) then (
            local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri ) ,
            local:members-down-1($tei//tei:body, "body", 1, $doc-uri)) 

         else () ,

        (: include back and its children :)
        if ($tei//tei:back) then (
            local:citable-unit("back", 1, (), "back", $tei//tei:back, $doc-uri ) ,
            local:members-down-1($tei//tei:back, "back", 1, $doc-uri)) 
        else ()
        )

    
    return
    map:merge( ($basic-response-map, map{"member" : $member}) )

 };

(:~ 
 : Navigate a resource on level 3
 :
 : tests/test_navigation_endpoint.py::test_navigation_two_down_response_validity
 : request URI: https://dev.dracor.org/api/v1/dts/navigation?resource=https://dev.dracor.org/id/test000001&down=3
 :
 : Does the same as local:navigation-level2 but also include grandchildren
 :)
declare function local:navigation-level3($tei as element(tei:TEI)) {

    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)
     
    (:Will add down parameter here:)
    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;down=3"
     
    let $basic-response-map := local:navigation-basic-response($tei, $request-id, "", "", "") (: use the default uri templates:)
    
    let $member :=
        (
            (: include front = level 1 then followed by all children and grandchildren of front :)
        if ($tei//tei:front) then ( 
            local:citable-unit("front", 1, (), "front", $tei//tei:front, $doc-uri ) ,
            local:members-down-2($tei//tei:front, "front", 1, $doc-uri)) 
            else () ,

        (: include body and its children and grandchildren :)
        if ($tei//tei:body) then (
            local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri ) ,
            local:members-down-2($tei//tei:body, "body", 1, $doc-uri)) 

         else () ,

        (: include back and its children and gradchildren :)
        if ($tei//tei:back) then (
            local:citable-unit("back", 1, (), "back", $tei//tei:back, $doc-uri ) ,
            local:members-down-2($tei//tei:back, "back", 1, $doc-uri)) 
        else ()
        )

    
    return
    map:merge( ($basic-response-map, map{"member" : $member}) )

 };

(:~ 
 : Navigate a resource on level 4
 :
 : Does the same as local:navigation-level3 but also include grand-grandchildren
 :)
declare function local:navigation-level4($tei as element(tei:TEI)) {

    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)
     
    (:Will add down parameter here:)
    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;down=4"
     
    let $basic-response-map := local:navigation-basic-response($tei, $request-id, "", "", "") (: use the default uri templates:)
    
    let $member :=
        (
            (: include front = level 1 then followed by all children and grandchildren of front :)
        if ($tei//tei:front) then ( 
            local:citable-unit("front", 1, (), "front", $tei//tei:front, $doc-uri ) ,
            local:members-down-3($tei//tei:front, "front", 1, $doc-uri)) 
            else () ,

        (: include body and its children and grandchildren :)
        if ($tei//tei:body) then (
            local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri ) ,
            local:members-down-3($tei//tei:body, "body", 1, $doc-uri)) 

         else () ,

        (: include back and its children and gradchildren :)
        if ($tei//tei:back) then (
            local:citable-unit("back", 1, (), "back", $tei//tei:back, $doc-uri ) ,
            local:members-down-3($tei//tei:back, "back", 1, $doc-uri)) 
        else ()
        )

    
    return
    map:merge( ($basic-response-map, map{"member" : $member}) )

 };

(:~ 
 : Navigate a resource: get whole citeTree
 :
 : produces the response on the navigation endpoint in which down=-1
 :)
declare function local:navigation-whole-citeTree($tei as element(tei:TEI)) {

    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)
     
    (:Will add down parameter here:)
    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;down=-1"
     
    let $basic-response-map := local:navigation-basic-response($tei, $request-id, "", "", "") (: use the default uri templates:)
    
    

    (: members can come from 
    local:navigation-level1,local:navigation-level2, local:navigation-level4 
    and local:navigation-level4 depending on the maximum cite depth :)

    let $citeDepth := $basic-response-map?resource?citationTrees?1?maxCiteDepth
    
    (: members can come from 
    local:navigation-level1,local:navigation-level2, local:navigation-level4 
    and local:navigation-level4 depending on the maximum cite depth :)

    let $member :=
        if ($citeDepth eq 1) then
            local:navigation-level1($tei)?member
        else if ($citeDepth eq 2) then
            local:navigation-level2($tei)?member
        else if ($citeDepth eq 3) then
            local:navigation-level3($tei)?member
        else if ($citeDepth eq 4) then
            local:navigation-level4($tei)?member
        else
            ()
        
    return 
        map:merge( ($basic-response-map, map{"member" : $member}) )

 };

(:~
: Helper function to generate a CitableUnit
:)
 declare function local:citable-unit($identifier, $level, $parent, $cite-type, $tei-fragment as element(), $resource ) {
    (: not totally sure if this is bullet-proof :)
    let $dublinCore := local:extract-dc-from-tei-fragment($tei-fragment)
    
    (: This is not in the spec, but I would like to have a link to the document endpoint to easily request the passage :)
    (: let $passage := $ddts:documents-base || "?resource=" || $resource || "&amp;ref=" || $identifier || "{&amp;mediaType}" :)
    
    let $citeable-unit-data := map {
        "@type": "CitableUnit",
        "identifier": $identifier,
        "level" : $level,
        "parent" : $parent,
        "citeType": $cite-type
        (: ,"passage" : $passage :)
    }
    
    return
        if ($dublinCore instance of map(*) ) then map:merge( ($citeable-unit-data, map{"dublinCore": $dublinCore}) )
    else $citeable-unit-data 
 };

(:~
: Helper function to extract dublin core metatada of a TEI fragment becoming a CiteableUnit
: Includes dc metadata if there is a head element in the div
:)
 declare function local:extract-dc-from-tei-fragment($tei-fragment as element()) {
    (: strangely this only works for body head, maybe in the front there are multiple head elements? 
    one solution would be to restrict it to body div heads only, but it also works if i just take the first head element
    to ultimately solve this one would need to have a closer look at the head elements
    :)
    if ($tei-fragment/name() eq "div") then
        if ($tei-fragment[tei:head]) then  
            map {"title" : normalize-space($tei-fragment/tei:head[1]/text())}
        else ()
    else ()

 };



(:~ 
: This is the function to generate the response of the navigation endpoint in the original pre-alpha implementation
: it is DEPRECATED. I keep it at the moment because I might want to re-use some code snippets
:)
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
         "@context" : $ddts:context , (: TODO: change this for alpha-1 :)
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
 : Can be used to retrieve descendants of a subdivision
 : TODO: This is still the code of pre-alpha which I need to adapt to 1-alpha
 : a request that returned some data: http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000088&ref=body.div.1

 : :)
declare function local:descendants-of-subdivision($tei, $ref, $down) {

    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;ref=" || $ref || "&amp;down=" || $down

    let $basic-navigation-object := local:navigation-basic-response($tei, $request-id, "", "", "")

    (: need to include something in ref and member :)
    (: first ref:)
    
    let $tei-fragment := local:get-fragment-of-doc($tei, $ref)[2]/node()/node() (: this also returns a respone object somehow; the real fragment is in tei:TEI/dts:wrapper/..:)
    let $cite-type := local:get-cite-type-from-tei-fragment($tei-fragment)
    let $level := local:get-level-from-ref($ref)
    let $parent-string :=  local:get-parent-from-ref($ref)
    let $parent := if ($parent-string  eq "") then () else $parent-string
    let $ref-object := local:citable-unit($ref, $level, $parent, $cite-type, $tei-fragment, $doc-uri )
    
    (: this only works for a single level down but testing:)
    
    let $members := 
        if ( $down eq "1" ) then 
            local:members-down-1($tei-fragment, $ref, $level, $doc-uri)
        
        else if ($down eq "2") then 
            local:members-down-2($tei-fragment, $ref, $level, $doc-uri)
        
        else if ($down eq "3") then
            local:members-down-3($tei-fragment, $ref, $level, $doc-uri)
        
        else if ($down eq "-1") then
            let $maxCiteDepth := $basic-navigation-object?resource?citationTrees?1?maxCiteDepth
            return
                local:members-down-minus-1($tei-fragment, $ref, $level, $doc-uri, $maxCiteDepth)
        else ()
        
    
    return 
    map:merge((
        $basic-navigation-object, 
        map{"ref": $ref-object}, 
        map{"member" : $members}
        ))

};

(:~ 
: Construct an identifier of a CiteableUnit by counting preceeding siblings with the same name
: pseudo xPath ...
:)
declare function local:generate-id-of-citeable-unit($parent-id as xs:string, $tei-fragment as element()) as xs:string {
    if ($tei-fragment/name() eq "div") then 
        $parent-id || "/div[" || xs:string(count($tei-fragment/preceding-sibling::tei:div) + 1) || "]"
                        
    else if ($tei-fragment/name() eq "sp") then
        $parent-id || "/sp[" || xs:string(count($tei-fragment/preceding-sibling::tei:sp) + 1) || "]"
                        
    else if ($tei-fragment/name() eq "stage") then
        $parent-id || "/stage[" || xs:string(count($tei-fragment/preceding-sibling::tei:stage) + 1) || "]" 
                        
    else if ($tei-fragment/name() eq "set") then
        $parent-id || "/set[" || xs:string(count($tei-fragment/preceding-sibling::tei:set) + 1) || "]" 

    else if ($tei-fragment/name() eq "titlePage") then
        $parent-id || "/titlePage[" || xs:string(count($tei-fragment/preceding-sibling::tei:set) + 1) || "]"

    else ""
};


(:~ 
: Retrieve substructures one level down
: parameter down eq "1"
: this is used by local:descendants-of-subdivision to retrieve the member items that are one level below
:)
declare function local:members-down-1($tei-fragment as element(), $ref as xs:string, $level as xs:int, $doc-uri as xs:string) {
    for $item in $tei-fragment/element()
            return
                (: only for elements that are CiteableUnits :)
                if ( 
                    $item/name() eq "div" or 
                    $item/name() eq "sp" or 
                    $item/name() eq "stage" or
                    $item/name() eq "set" or 
                    $item/name() eq "titlePage") then

                    (:need to construct an identifier for this element :)
                    (: this should go into designated function :)
                    let $item-identifier := local:generate-id-of-citeable-unit($ref, $item)
                    
                    return local:citable-unit($item-identifier, $level + 1 , $ref, local:get-cite-type-from-tei-fragment($item) , $item, $doc-uri )
                else ()

};

declare function local:members-down-2($tei-fragment, $ref, $level, $doc-uri) {
    for $item in $tei-fragment/element()
            return
                
                
                (: only for elements that are CiteableUnits :)
            
                if ( $item/name() eq "div" or 
                    $item/name() eq "sp" or 
                    $item/name() eq "stage" or
                    $item/name() eq "set" or
                    $item/name() eq "titlePage"
                    ) then

                    (:need to construct an identifier for this element :)
                    let $item-identifier := local:generate-id-of-citeable-unit($ref, $item)
                    
                    return
                    (: this and all it's sub elements:) 
                    (
                        local:citable-unit($item-identifier, $level + 1 , $ref, local:get-cite-type-from-tei-fragment($item) , $item, $doc-uri ) ,
                        local:members-down-1($item, $item-identifier, $level + 1, $doc-uri)
                    )
                else ()            
                
};

declare function local:members-down-3($tei-fragment, $ref, $level, $doc-uri) {
    for $item in $tei-fragment/element()
            return
                
                
                (: only for elements that are CiteableUnits :)
                if ( $item/name() eq "div" or 
                $item/name() eq "sp" or 
                $item/name() eq "stage" or
                $item/name() eq "set" or
                $item/name() eq "titlePage"
                ) then

                    (:need to construct an identifier for this element :)
                    let $item-identifier := local:generate-id-of-citeable-unit($ref, $item)
                    
                    return
                    (: this and all it's sub elements:) 
                    (
                        local:citable-unit($item-identifier, $level + 1 , $ref, local:get-cite-type-from-tei-fragment($item) , $item, $doc-uri ) ,
                        local:members-down-2($item, $item-identifier, $level + 1, $doc-uri)
                    )
                else ()            
                
};


declare function local:members-down-minus-1($tei-fragment, $ref, $level, $doc-uri, $maxCiteDepth) {
    (: we are starting at body so the level needs to be reduced by 1:)
    if ($maxCiteDepth eq 2) then
        local:members-down-1($tei-fragment, $ref, $level, $doc-uri)
    else if ($maxCiteDepth eq 3) then
        local:members-down-2($tei-fragment, $ref, $level, $doc-uri)
    else if ($maxCiteDepth eq 4) then
        local:members-down-3($tei-fragment, $ref, $level, $doc-uri)
    else ()

};



(:~
: Navigation endpoint displays information about a CiteableUnit as pointed to in the spec 
: https://distributed-text-services.github.io/specifications/versions/1-alpha/#uri-for-navigation-endpoint-requests;
: combination of params down = absent, ref= present, start/end = absent
: "Information about the CitableUnit identified by ref. No member property in the Navigation object."local:citeable-unit-by-ref()
:
: @param $tei TEI document of the resource
: @param $ref fragment identifier

:)
declare function local:citeable-unit-by-ref($tei, $ref) {
    
    let $tei-fragment := local:get-fragment-of-doc($tei, $ref)[2]/node()/node() (: this also returns a respone object somehow; the real fragment is in tei:TEI/dts:wrapper/..:)
    let $cite-type := local:get-cite-type-from-tei-fragment($tei-fragment)
    let $level := local:get-level-from-ref($ref)
    let $parent-string :=  local:get-parent-from-ref($ref)
    let $parent := if ($parent-string  eq "") then () else $parent-string


    (:re-use some object returned by this endpoint already :)
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    let $ref-object := local:citable-unit($ref, $level, $parent, $cite-type, $tei-fragment, $doc-uri )
    
    
    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;ref=" || $ref
    (: passage-url, collecion-url, navigation-url to overwrite after $request-id :)
    (: let $passage-url := $ddts:documents-base || "?resource=" || $doc-uri || "&amp;ref=" || $ref :)
    (: let $navigation-url := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;ref=" || $ref  || "{&amp;down}" :)
    let $basic-response-object := local:navigation-basic-response($tei, $request-id, "" ,"", "" ) (:could theoretically overwrite:)

    let $ref-map := map {
        "ref" : $ref-object
    }
    
    return
    map:merge( ($basic-response-object, $ref-map) )
    
    
};

(:~ Helper function that detects the citeType from a tei fragment :)
declare function local:get-cite-type-from-tei-fragment($tei-fragment as element()) {
    if ($tei-fragment/name() eq "sp") then "speech"
    else if ($tei-fragment/name() eq "stage") then "stage_direction"
    else if ($tei-fragment/name() eq "body") then "body"
    else if ($tei-fragment/name() eq "front") then "front"
    else if ($tei-fragment/name() eq "back") then "back"
    else if ($tei-fragment/name() eq "div") then
        if ($tei-fragment/@type/string() eq "act") then "act"
        else if ($tei-fragment/@type/string() eq "scene") then "scene"
        else lower-case($tei-fragment/@type/string())
    else if ($tei-fragment/name() eq "set") then "setting"
    else if ($tei-fragment/name() eq "titlePage") then "title_page" 
    else "unknown" || "[Debug: " || $tei-fragment/name() || "]"
};

(:~
 : Helper function that parses the identifier $ref to understand at which level in the citationTree the 
 : requested element seems to be located;
 : examples of such $ref values are body = level1 , body/div[2]/sp[1] = level3, body/div[2]/div[1]/sp[1] = level4
 : this function counts the slashes in the xPath identifier as a proxy
:)
declare function local:get-level-from-ref($ref as xs:string) as xs:int {
    count(tokenize($ref, "/"))
};


(:~
: Helper Function to get parent of a CiteableUnit form the identifier ref
:)
declare function local:get-parent-from-ref($ref as xs:string) as xs:string {
    string-join(tokenize($ref, "/")[position() != last()], "/")
};

declare function local:navigation-basic-response($tei as element(tei:TEI), $request-id as xs:string, $passage-url as xs:string, $collection-url as xs:string, $navigation-url as xs:string) {

     let $doc-id := $tei/@xml:id/string()
     let $doc-uri := local:id-to-uri($doc-id)
    
    (: URI templates :)
    (: QUESTION: do I need to set them dynamically, i.e. overwrite as uncommented, or are they staying the same no matter what the request is :)
    (:
    let $passage := if ($passage-url != "") then $passage-url else $ddts:documents-base || "?resource=" || $doc-uri || "{&amp;ref,start,end}"
    let $collection := if ($collection-url != "") then $collection-url else $ddts:collections-base || "?id=" || $doc-uri || "{&amp;nav}"
    let $navigation := if ($navigation-url != "") then $navigation-url else $ddts:navigation-base || "?resource=" || $doc-uri || "{&amp;ref,start,end,down}" (: maybe add also page, althoug not plan to implement it now:)
    :)
    (: 'passage' has been renamed to 'document' in "unstable" see https://github.com/mromanello/DTS-validator/blob/6f1f0fb6c78a815411c6c5cce57840599dc2c475/NOTES.md#validation-reports-explained :)
    let $document := $ddts:documents-base || "{?resource,ref,start,end,mediaType}"
    (: according to the spec this endpoint only includes passage and navigation in the Navigation object :)
    (: let $collection := $ddts:collections-base || "{?id,nav}" :)
    let $navigation := $ddts:navigation-base || "{?resource,ref,start,end,down}"
    
    let $citationTrees := local:generate-citationTrees($tei)

    (: maybe this could also be delegated to the function that does this for the collection endpoint? :)
    (: maybe dublin core would be nice? :)
    (: according to the spec collection IS REQUIRED to be included in the resource; this is currently not in the examples :)
    let $collection := $ddts:collections-base || "?id=" || $doc-uri || "{&amp;nav}"

    let $resource := map {
        "@id" : $doc-uri,
        "@type" : "Resource",
        "citationTrees" : $citationTrees,
        "mediaTypes" : array {"application/tei+xml"},
        "collection" : $collection
    }

     return
     (: added @type = 'Navigation' to the response object see https://github.com/mromanello/DTS-validator/blob/6f1f0fb6c78a815411c6c5cce57840599dc2c475/NOTES.md#validation-reports-explained:)
     map{
         "@context" : $ddts:dts-jsonld-context-url,
         "@id" : $request-id,
         "@type" : "Navigation",
         "dtsVersion" : $ddts:spec-version,
         (: "passage" has been renamed to "document" in version "unstable" :)
         "document" : $document,
         (: "collection" : $collection, :) (: this according to the spec:)
         "navigation" : $navigation,
         "resource" : $resource
     }
 };

(:~
: "Information about the CitableUnit identified by ref along with a member property 
: that is an array of CitableUnits that are siblings (sharing the same parent) including 
: the current CitableUnit identified by ref"
: This is very much spaghetti code, but it seems to work none the less.. 
:)
 declare function local:siblings-of-citeable-unit-by-ref($tei as element(tei:TEI), $ref as xs:string) {
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;ref=" || $ref || "&amp;down=0"

    let $basic-navigation-object := local:navigation-basic-response($tei, $request-id, "", "", "")
    
    (: need to include something in ref and member :)
    (: first ref:)
    let $tei-fragment := local:get-fragment-of-doc($tei, $ref)[2]/node()/node() (: this also returns a respone object somehow; the real fragment is in tei:TEI/dts:wrapper/..:)
    let $cite-type := local:get-cite-type-from-tei-fragment($tei-fragment)
    let $level := local:get-level-from-ref($ref)
    let $parent-string :=  local:get-parent-from-ref($ref)
    let $parent := if ($parent-string  eq "") then () else $parent-string
    let $ref-object := local:citable-unit($ref, $level, $parent, $cite-type, $tei-fragment, $doc-uri )
    
    (: Be careful, as Wolfgang Meier once said: eval() is evil.. 
    to make eval less evil, check if ref conforms to a certain xpath and does not contain some bad code
    This should be done before calling this function
    Generally speaking this is a good way of retrieving segments identified by the xPath-ish ID
    :)
    
    let $self-elem := util:eval("$tei/tei:text/tei:" || replace($ref, "/", "/tei:"))
    let $pre-elems := util:eval("$tei/tei:text/tei:" || replace($ref, "/", "/tei:"))/preceding-sibling::element()
    let $post-elems :=  util:eval("$tei/tei:text/tei:" || replace($ref, "/", "/tei:"))/following-sibling::element()

    let $ref-items := tokenize($ref, "/")[position() != last()]
    let $ref-base := string-join($ref-items, "/")

    let $member-elems := ($pre-elems, $self-elem, $post-elems)
    let $members := 
        for $item in $member-elems return
            (: TODO: check if these are all Citeable Units :)
            if ( 
                $item/name() eq "div" or 
                $item/name() eq "sp" or 
                $item/name() eq "stage" or 
                $item/name() eq "body" or 
                $item/name() eq "front" or 
                $item/name() eq "back" ) then
                let $pos := xs:string(count($item/preceding-sibling::element()[./name() eq $item/name()]) + 1)
                let $identifier-candiate := $ref-base || "/" || $item/name() || "[" || $pos || "]"
                let $identifier := 
                    if ($identifier-candiate eq "/front[1]") then "front"
                    else if ($identifier-candiate eq "/body[1]") then "body"
                    else $identifier-candiate
                let $cite-type := local:get-cite-type-from-tei-fragment($item) 
            
                return 
                    local:citable-unit($identifier, $level, $parent, $cite-type, $item, $doc-uri )
            else ()
        


    return
    map:merge( ($basic-navigation-object, map{ "ref" : $ref-object}, map{ "member" : $members} ) )
    
 };

(:~ Function to get the inner border units of a range, e.g. start and end :)
declare function local:bordering-citeable-unit-of-range($tei, $ref, $doc-uri) {
    let $tei-fragment := local:get-fragment-of-doc($tei, $ref)[2]/node()/node() (: this also returns a respone object somehow; the real fragment is in tei:TEI/dts:wrapper/..:)
    let $cite-type-fragment := local:get-cite-type-from-tei-fragment($tei-fragment)
    let $level := local:get-level-from-ref($ref)
    let $parent-string :=  local:get-parent-from-ref($ref)
    let $parent := if ($parent-string  eq "") then () else $parent-string
    let $object := local:citable-unit($ref, $level, $parent, $cite-type-fragment, $tei-fragment, $doc-uri )
    return $object

};


 (:~
 : "Information about the CitableUnits identified by start and by end. No member property in the Navigation object."
 :)
 declare function local:citeable-units-by-start-end($tei, $start, $end) {
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;start=" || $start || "&amp;end=" || $end

    let $basic-navigation-object := local:navigation-basic-response($tei, $request-id, "", "", "")

    (: include start and end :)

    let $start-object := local:bordering-citeable-unit-of-range($tei, $start, $doc-uri)

    (: same for end :)
    let $end-object := local:bordering-citeable-unit-of-range($tei, $end, $doc-uri)

    (: This also should include member! :)
    (: assume that the fragment returned by the document endpoint is already useable and just use 
    this for creating the members :)
    (: e.g. http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000638&start=body/div[2]&end=body/div[4] :)
   

   let $members := if ( $start eq "front" and $end eq "body") then
                    ( $start-object, $end-object ) (: this is range front/body as in the dts validator; 
                    I hardcode this because I don't thing somebody would really request it:)

                    (: the other cases with top level elements; it could request front to back :)
                    (: Still have to check if that works! :)
                    else if ( $start eq "front" and $end eq "back") then
                        let $body := local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri )
                        return ($start-object, $body ,$end-object)
                    
                    else if ( $start eq "body" and $end eq "back" ) then 
                        ( $start-object, $end-object ) (: also probably nobody would request that :)
                    

                    (: this works for body structures, e.g. /body/div[2] to /body/div[7] :)
                    (: somewhere before all is returned there should be a warning if something strange is requested :)
                    else if (matches($start,"^body/div\[\d+\]$") and  matches($end,"^body/div\[\d+\]$")) then 
                        local:top_level_members_of_range($tei, $start, $end)

                    (: this works for body structures where we have a act - scene structure, e.g. from body/div[2]/div[3] to body/div[2]/div[5] :)
                    else if ( matches($start, "^body/div\[\d+\]/div\[\d+\]$") )
                        then local:top_level_members_of_range($tei, $start, $end)

                    (: this works for http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000638&start=body/div[2]/stage[1]&end=body/div[2]/sp[5]  :)
                    else if (matches($start, "^body/div\[\d+\]/(sp|stage)\[\d+\]") ) then
                        local:sp_stage_level3_members_of_range($tei, $start, $end)


                    (: e.g. ger000171:)
                    (: http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000171&start=body/div[2]/div[3]&end=body/div[2]/div[5]: :)
                    else if ( matches($start, "^body/div\[\d+\]/div\[\d+\]/(sp|stage)\[\d+\]") )
                        then "implement body/div[1]/div[1]/sp|stage"
                    
                    else ()
    

    return 
        map:merge( ($basic-navigation-object, map{"start" : $start-object}, map{"end" : $end-object}, map{"member" : $members}) ) 
        
 };

(:~ should handle the case of getting the members of 
start=body/div[x]/stage[y]&end=body/div[z]/sp[a] 
:)
 declare function local:sp_stage_level3_members_of_range($tei as element(tei:TEI), $start as xs:string, $end as xs:string) {
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)
    let $start-object := local:bordering-citeable-unit-of-range($tei, $start, $doc-uri)
    let $end-object := local:bordering-citeable-unit-of-range($tei, $end, $doc-uri)
    
    (: not sure if I really need them because I can retrieve the fragment via the alreay implemented funcion – see other :)
    let $start-xpath := "$tei//" || replace(replace($start, "/","/tei:"),"body", "tei:body")
    
    let $start-elem := util:eval($start-xpath)

    (: get the number of preceding elements sp and stage inside the same parent. 
    We need this to construct the identifier in the requested range  :)
    let $preceding-sp-count := count($start-elem/preceding-sibling::tei:sp)
    let $preceding-stage-count := count($start-elem/preceding-sibling::tei:stage)
    
    (: use the designated function to get the range  :)
    let $tei-fragments := local:get-fragment-range($tei, $start, $end)/dts:wrapper/element()
    let $parent := local:get-parent-from-ref($start) 
    let $members := for $item in $tei-fragments 
        let $identifier := 
            if ($item/name() eq "sp") then 
                (: we need to check how many sp are before this item and add the number of sp before the start of the range :)
                let $pos := count($item/preceding-sibling::tei:sp) + $preceding-sp-count + 1
                    return $parent || "/sp[" || xs:string($pos) || "]"
            
            else if ($item/name() eq "stage") then 
                let $pos := count($item/preceding-sibling::tei:stage) + $preceding-stage-count + 1
                    return $parent || "/stage[" || xs:string($pos) || "]"

            (: if the item is not a sp or a stage, this is probably not triggered :)
            else "unknown"
        
        return local:citable-unit($identifier, 3, $parent, local:get-cite-type-from-tei-fragment($item), $item, $doc-uri )
    
    return $members

 };


(:~ Get the members of a range requested via the navigation endpoint
: this works for http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000638&start=body/div[2]&end=body/div[4]
: http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000171&start=body/div[2]/div[3]&end=body/div[2]/div[5]
but would not work for mixed element range, e.g. sp/stage
:)
declare function local:top_level_members_of_range($tei, $start as xs:string, $end as xs:string) {

    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    (: This also should include member! :)
    (: assume that the fragment returned by the document endpoint is already useable and just use 
    this for creating the members :)
    (: e.g. http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000638&start=body/div[2]&end=body/div[4] :)
    let $tei_fragment := local:get-fragment-range($tei, $start, $end)/dts:wrapper
   
    let $parent-string-start :=  local:get-parent-from-ref($start)
    let $parent-start := if ($parent-string-start  eq "") then () else $parent-string-start
   
    let $level-start := local:get-level-from-ref($start)

    (: this is the position of the div in body :)
    let $start-pos-in-parent := 
        (: level 2 segments div :)
        if ( matches($start, 'body/div\[\d+\]$')) then
            xs:int(replace(replace($start, "body/div\[",""),"\]",""))
        (: level 3 segments div :)
        else if (matches($start, 'body/div\[\d+\]/div\[\d+\]$')) then
            xs:int(replace(replace($start, "body/div\[\d+\]/div\[",""),"\]",""))
        else 0
        (: this will work only for elements div of the same type on the same level! :)


        let $members := 
            for $item at $pos in $tei_fragment/(tei:div|tei:stage|tei:sp)
        
                let $cite-type-item := local:get-cite-type-from-tei-fragment($item)
        
                let $item-id := 
                    if ($item/name() eq "div") 
                        then $parent-start || "/div[" || xs:string($start-pos-in-parent - 1 + $pos) || "]"
                (: if this is done for anything than div it is hard to get the start ID to start counting; I would need to
                know with position is the stage/sp element in the parent div (which I can not get from the extracted TEI fragment) :)

        
                    else "unknown"
            return
                local:citable-unit($item-id, $level-start, $parent-start, $cite-type-item, $item, $doc-uri )
    
    return $members 

};

(:~
Produce response if start/end and down
:)
declare function local:citeable-units-by-start-end-with-members-down-1($tei, $start as xs:string, $end as xs:string, $down as xs:string) {
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;start=" || $start || "&amp;end=" || $end || "&amp;down=" || $down
    
    let $basic-navigation-object := local:navigation-basic-response($tei, $request-id, "", "", "")
    
    let $start-object := local:bordering-citeable-unit-of-range($tei, $start, $doc-uri)
    let $end-object := local:bordering-citeable-unit-of-range($tei, $end, $doc-uri)

    (: we implement this only if start and and is in the same parent fragment, e.g. body! :)

    (: this would already get the right document snippet:)
    (: http://localhost:8088/api/v1/dts/document?resource=http://localhost:8088/id/ger000638&start=body/div[2]&end=body/div[4] :)

    (: DTS Validator tries start=front, end=body, down=1
    I hardcode this because I don't think :)
    let $members := 
        if ($start eq "front" and $end eq "body") then
        (
            $start-object,
            local:members-down-1($tei//tei:front, "front", 1, $doc-uri),
            $end-object,
            local:members-down-1($tei//tei:body, "body", 1, $doc-uri)
        )

        else if ($start eq "front" and $end eq "back") then 
            let $body := local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri )
            return
                (
                    $start-object,
                    local:members-down-1($tei//tei:front, "front", 1, $doc-uri),
                    $body,
                    local:members-down-1($tei//tei:body, "body", 1, $doc-uri),
                    $end-object,
                    local:members-down-1($tei//tei:back, "back", 1, $doc-uri)
                )
        
        else if ($start eq "body" and $end eq "back") then 
            (
            $start-object,
            local:members-down-1($tei//tei:body, "body", 1, $doc-uri),
            $end-object,
            local:members-down-1($tei//tei:back, "back", 1, $doc-uri)
            )

        (: the more generic case: get the members without down then iterate and get the children of each item :)
        (: this works for http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000638&start=body/div[2]&end=body/div[4]&down=2 :)
        else (
            let $top_level_members := local:top_level_members_of_range($tei, $start, $end)
            
            for $item in $top_level_members
                let $tei-fragment := local:get-fragment-of-doc($tei, $item?identifier)[2]/node()/node()[1] (: strage, but this yields the right result :)

            return ( $item, local:members-down-1($tei-fragment, $item?identifier, $item?level , $doc-uri)) 
              
        )

    return
    map:merge( ($basic-navigation-object, map{"start" : $start-object}, map{"end" : $end-object}, map{"member" : $members}) ) 
};


(:~ Checks if the citeable units identified by start and end share the same parent:)
declare function local:start_end_share_same_parent($start as xs:string, $end as xs:string, $tei as element(tei:TEI)) {
    (: we expect that start and end have been validated already by the function validate-ref
    which uses the xPath: "^(body|front|back)(/(div|stage|sp|set|castList)\[\d+\])*?$"
    this prevents us of having any xPath functions called :)
    (: the problem is that the xPaths do not include namespaces :)
    let $start-xpath := local:xpathish-id-to-xpath($start)
    let $end-xpath := local:xpathish-id-to-xpath($end)
    return
        if ( util:eval($start-xpath)/parent::element() eq util:eval($end-xpath)/parent::element() ) then
            true()
        else
            false()
};

(:~ Transforms a xPath-ish identifier to a string that is a real xPath an can be evaluated with util:eval
: It is necessary to make sure that the xPath evaluated is actually safe, i.e. use validate-ref function before passing something on to util:eval
:)
declare function local:xpathish-id-to-xpath($id) {
    "$tei//" || replace(replace(replace(replace($id, "/", "/tei:"), "body", "tei:body"), "front", "tei:front"), "back", "tei:back")
};

(:~ Go down two levels when requesting a range 
: http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000171&start=body/div[2]&end=body/div[4]&down=2
:)
declare function local:citeable-units-by-start-end-with-members-down-2($tei, $start as xs:string, $end as xs:string, $down as xs:string) {
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;start=" || $start || "&amp;end=" || $end || "&amp;down=" || $down
    
    let $basic-navigation-object := local:navigation-basic-response($tei, $request-id, "", "", "")
    
    let $start-object := local:bordering-citeable-unit-of-range($tei, $start, $doc-uri)
    let $end-object := local:bordering-citeable-unit-of-range($tei, $end, $doc-uri)

    let $members := 
        if ($start eq "front" and $end eq "body") then
        (
            $start-object,
            (: for the body we can not go down 2 :)
            local:members-down-1($tei//tei:front, "front", 1, $doc-uri),
            $end-object,
            local:members-down-2($tei//tei:body, "body", 1, $doc-uri)
        )

        else if ($start eq "front" and $end eq "back") then 
            let $body := local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri )
            return
                (
                    $start-object,
                    local:members-down-1($tei//tei:front, "front", 1, $doc-uri),
                    $body,
                    (: body can go down 2, the others not!:)
                    local:members-down-2($tei//tei:body, "body", 1, $doc-uri),
                    $end-object,
                    local:members-down-1($tei//tei:back, "back", 1, $doc-uri)
                )
        
        else if ($start eq "body" and $end eq "back") then 
            (
            $start-object,
            (: body can go down 2 back probably not :)
            local:members-down-2($tei//tei:body, "body", 1, $doc-uri),
            $end-object,
            local:members-down-1($tei//tei:back, "back", 1, $doc-uri)
            )

        (: the more generic case: get the members without down then iterate and get the children of each item :)
        (: this works for http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000638&start=body/div[2]&end=body/div[4]&down=2 :)
        else (
            let $top_level_members := local:top_level_members_of_range($tei, $start, $end)
            
            for $item in $top_level_members
                let $tei-fragment := local:get-fragment-of-doc($tei, $item?identifier)[2]/node()/node()[1] (: strage, but this yields the right result :)

            return ( $item, local:members-down-2($tei-fragment, $item?identifier, $item?level , $doc-uri)) 
              
        )

    return
    map:merge( ($basic-navigation-object, map{"start" : $start-object}, map{"end" : $end-object}, map{"member" : $members}) ) 
};


(:~ Go down a range three levels
: this is more of a theoretical than an actual practical example because actually going down three levels in a range only makes sense
for a range of front to body ... don't really know who would ever want to do this, but well...
:)
declare function local:citeable-units-by-start-end-with-members-down-3($tei as element(tei:TEI), $start as xs:string, $end as xs:string, $down as xs:string) {
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)

    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;start=" || $start || "&amp;end=" || $end || "&amp;down=" || $down
    
    let $basic-navigation-object := local:navigation-basic-response($tei, $request-id, "", "", "")
    
    let $start-object := local:bordering-citeable-unit-of-range($tei, $start, $doc-uri)
    let $end-object := local:bordering-citeable-unit-of-range($tei, $end, $doc-uri)

    let $members := 
        if ($start eq "front" and $end eq "body") then
        (
            $start-object,
            (: for the body we can not go down 3 :)
            local:members-down-1($tei//tei:front, "front", 1, $doc-uri),
            $end-object,
            local:members-down-3($tei//tei:body, "body", 1, $doc-uri) 
        )

        else if ($start eq "front" and $end eq "back") then 
            let $body := local:citable-unit("body", 1, (), "body", $tei//tei:body, $doc-uri )
            return
                (
                    $start-object,
                    local:members-down-1($tei//tei:front, "front", 1, $doc-uri),
                    $body,
                    (: body can go down 3, the others not!:)
                    local:members-down-3($tei//tei:body, "body", 1, $doc-uri),
                    $end-object,
                    local:members-down-1($tei//tei:back, "back", 1, $doc-uri)
                )
        
        else if ($start eq "body" and $end eq "back") then 
            (
            $start-object,
            (: body can go down 3 back probably not :)
            local:members-down-3($tei//tei:body, "body", 1, $doc-uri),
            $end-object,
            local:members-down-1($tei//tei:back, "back", 1, $doc-uri)
            )

        (: the more generic case: get the members without down then iterate and get the children of each item :)
        (: this works for http://localhost:8088/api/v1/dts/navigation?resource=http://localhost:8088/id/ger000638&start=body/div[2]&end=body/div[4]&down=2 :)
        else (
            let $top_level_members := local:top_level_members_of_range($tei, $start, $end)
            
            for $item in $top_level_members
                let $tei-fragment := local:get-fragment-of-doc($tei, $item?identifier)[2]/node()/node()[1] (: strage, but this yields the right result :)

            return ( $item, local:members-down-3($tei-fragment, $item?identifier, $item?level , $doc-uri))  
              
        )

    return
    map:merge( ($basic-navigation-object, map{"start" : $start-object}, map{"end" : $end-object}, map{"member" : $members}) )
};


(:~ Get the whole citeTree of a range 
: Because there are currently no sanity checks for the down parameter in place, requesting down eq 3 should always do the trick
:)
declare function local:navigation-range-whole-citeTree($tei as element(tei:TEI), $start as xs:string, $end as xs:string) {
    let $doc-id := $tei/@xml:id/string()
    let $doc-uri := local:id-to-uri($doc-id)
     
    (:Will add down parameter here:)
    let $request-id := $ddts:navigation-base || "?resource=" || $doc-uri || "&amp;start=" || $start || "&amp;end=" || $end || "&amp;down=-1"
     
    let $basic-response-map := local:navigation-basic-response($tei, $request-id, "", "", "") (: use the default uri templates:)
    
    

    (: members can come from local:citeable-units-by-start-end-with-members-down-3($tei as element(tei:TEI), $start as xs:string, $end as xs:string, $down as xs:string):)

    let $member := local:citeable-units-by-start-end-with-members-down-3($tei,$start,$end,"3")?member
        
    return 
        map:merge( ($basic-response-map, map{"member" : $member}) )
};

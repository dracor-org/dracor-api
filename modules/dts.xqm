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
declare variable $ddts:ns-dts := "https://w3id.org/dts/api#";
declare variable $ddts:ns-hydra := "https://www.w3.org/ns/hydra/core#";
declare variable $ddts:ns-dc := "http://purl.org/dc/terms/";


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

declare
  %rest:GET
  %rest:path("/dts/collections")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function ddts:collections() {
  (: Get the corpora, get info needed for the member-array :)
  let $corpora := collection($config:data-root)//tei:teiCorpus
  let $corpus-members-maps :=
    for $corpus in $corpora
      let $info := dutil:get-corpus-info($corpus)
      let $name := $info?name
      (: would have to get more data, e.g. number of plays in the collection. important! :)
      order by $name
      return
        map {
          "@id" : $name ,
          "title" : $info?title ,
          "description" : $info?description ,
          "@type" : "Collection" ,
          "dts:totalParents": 1
        }

  (: response :)

  let $context := map {
    "@vocab": $ddts:ns-hydra,
    "dc": $ddts:ns-dc,
    "dts": $ddts:ns-dts
  }

  let $members := array { $corpus-members-maps }

  let $id := "corpora"
  let $title := "DraCor Corpora"
  let $dublincore := map {}
  let $totalParents := 0
  let $totalChildren := count( $members )




  return
    map {
      "@context" : $context ,
      "@id": $id,
      "@type": "Collection" ,
      "dts:totalParents": $totalParents ,
      "dts:totalChildren": $totalChildren ,
      "title": $title,
      "member" : $members
    }
};

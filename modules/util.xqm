xquery version "3.1";

(:~
 : Module proving utility functions for dracor.
 :)
module namespace dutil = "http://dracor.org/ns/exist/util";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

(:~
 : Retrieve the speaker children of a given element return the distinct IDs
 : referenced in @who attributes of those ekements.
 :)
declare function dutil:distinct-speakers ($parent as element()) as item()* {
    let $whos := for $w in $parent//tei:sp/@who return tokenize($w, '\s+')
    for $ref in distinct-values($whos) return substring($ref, 2)
};

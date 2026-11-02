xquery version "3.1";

(:~
 : Collection trigger for the corpora collection
 :
 : The trigger only schedules jobs that update the data derived from the TEI
 : documents (see sync.xqm). The actual updates are not done here because
 : eXist-db runs triggers while holding write locks on the whole collection
 : hierarchy up to /db, which blocks all other queries. For the same reason
 : this module must stay lightweight: eXist-db compiles it for every single
 : trigger event.
 :)
module namespace dt = "http://dracor.org/ns/exist/v1/trigger";

declare namespace trigger = "http://exist-db.org/xquery/trigger";

import module namespace queue = "http://dracor.org/ns/exist/v1/queue" at "queue.xqm";

declare function trigger:after-create-document($uri as xs:anyURI) {
  queue:enqueue($uri)
};

declare function trigger:after-update-document($uri as xs:anyURI) {
  queue:enqueue($uri)
};

declare function trigger:after-delete-document($uri as xs:anyURI) {
  queue:enqueue($uri)
};

declare function trigger:after-move-document(
  $new-uri as xs:anyURI,
  $uri as xs:anyURI
) {
  queue:enqueue($new-uri), queue:enqueue($uri)
};

declare function trigger:after-copy-document(
  $new-uri as xs:anyURI,
  $uri as xs:anyURI
) {
  queue:enqueue($new-uri), queue:enqueue($uri)
};

(:~
 : Schedule removal of the RDF of a corpus or play from Fuseki when its
 : collection is deleted (when deleting or reloading a corpus, deleting a play
 : or removing it through a webhook delivery).
 :)
declare function trigger:after-delete-collection($uri as xs:anyURI) {
  queue:enqueue($uri)
};

declare function trigger:after-move-collection(
  $new-uri as xs:anyURI,
  $uri as xs:anyURI
) {
  queue:enqueue($new-uri), queue:enqueue($uri)
};

declare function trigger:after-copy-collection(
  $new-uri as xs:anyURI,
  $uri as xs:anyURI
) {
  queue:enqueue($new-uri), queue:enqueue($uri)
};

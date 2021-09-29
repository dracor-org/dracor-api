xquery version "3.1";

import module namespace drdf = "http://dracor.org/ns/exist/rdf"
at "rdf.xqm";
import module namespace config = "http://dracor.org/ns/exist/config"
  at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/util"
  at "util.xqm";
import module namespace metrics = "http://dracor.org/ns/exist/metrics"
  at "metrics.xqm";

declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";

(:  let $play := dutil:get-doc("ger", "alberti-brot")/tei:TEI  :)
(: Egmont :)
(:  "ger000442", goethe-egmont :)
(:  let $play := dutil:get-doc("ger", "goethe-egmont")/tei:TEI :)
let $play := dutil:get-doc( "test", "lessing-emilia-galotti")/tei:TEI
(:  :let $play := dutil:get-doc("ger", "gutzkow-richard-savage")/tei:TEI :)

let $rdf-transformed := drdf:play-to-rdf($play)
(:  let $metrics := drdf:play-metrics-to-rdf("ger", "alberti-brot", "https://dracor.org/entity/ger000171", false())
return ($metrics)
:)
(:  let $years := dutil:get-years-iso($play) :)

(: let $play-info := dutil:get-play-info("ger", "alberti-brot") :)
(:  let $play-info := dutil:get-play-info("ger", "goethe-egmont") :)
let $play-info := dutil:get-play-info("test", "lessing-emilia-galotti")
(:  :let $play-info := dutil:get-play-info("ger", "gutzkow-richard-savage") :)
(:  return $play-info :)

(:
let $segments := drdf:segments-to-rdf($play-info?segments, "https://dracor.org/entity/ger000171", "Brot!" )
return $segments
:)

(:  let $cast := drdf:characters-to-rdf("ger", "alberti-brot", ""  , "https://dracor.org/entity/ger000171", true() , false()) :)
(:  let $cast := drdf:characters-to-rdf("ger", "goethe-faust-eine-tragoedie", ""  , "https://dracor.org/entity/ger000243", true() , false()) :)

(:  return $cast :)

(: genre :)
(:  let $text-classes := dutil:get-text-classes($play) :)
(:  let $tei-textClass :=  $play//tei:textClass
let $genre-rdf := drdf:textClass-genre-to-rdf($tei-textClass, "https://dracor.org/entity/ger000442")
:)

return $rdf-transformed

(: alberti-brot :)
(:  let $relations-rdf := drdf:relations-to-rdf($play-info?relations, "https://dracor.org/entity/ger000171" ) :)
(: goethe egmont :)
(:  :let $relations-rdf := drdf:relations-to-rdf($play-info?relations, "https://dracor.org/entity/ger000442" ) :)
(:  let $relations-rdf := drdf:relations-to-rdf($play-info?relations, "https://dracor.org/entity/ger000006" ) :)



(:  segments :)
(:  return () :)

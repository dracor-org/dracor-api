xquery version "3.1";

(:~
 : TEMPORARY: refresh the version index without authorization
 :
 : For testing the versioned /id/ resolver on dev.dracor.org, where neither
 : the admin password nor a corpus reload is at hand. REMOVE this module and
 : its lines in post-install.xq before merging (see dracor-api#435).
 :
 : Runs with elevated privileges (setuid admin, set in post-install.xq, as
 : for webhook.xqm), because the index has to be written to the database.
 : To keep that safe:
 :
 : - It reads nothing from the request: no parameters, no headers, no body.
 : - The source is fixed: $resolver:default-index-source (the public
 : dracor-version-index repository on GitHub). No URL can be passed in.
 : - It only loads the index of corpora that are already in the database,
 : and writes only to $resolver:versions-root.
 : - It runs at most once every $refresh:min-interval; otherwise 503 with
 : Retry-After (eXist does not accept 429 in rest:response).
 :
 : The worst a caller can do is reload the same public data every few
 : minutes.
 :)
module namespace refresh = "http://dracor.org/ns/exist/v1/id-index-refresh";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";
import module namespace resolver = "http://dracor.org/ns/exist/v1/resolver" at "resolver.xqm";

(: minimum interval between two refreshes, in seconds :)
declare variable $refresh:min-interval := 600;

declare variable $refresh:state-name := "refresh-state.xml";

(:~
 : Length of a dayTimeDuration in seconds
 :
 : Computed from its components: eXist 6.4 gets arithmetic on durations with
 : fractional seconds wrong (PT10M - PT1M24.665S yields P5DT23H8M).
 :)
declare function refresh:seconds($d as xs:dayTimeDuration) as xs:decimal {
  days-from-duration($d) * 86400 +
    hours-from-duration($d) * 3600 +
    minutes-from-duration($d) * 60 +
    seconds-from-duration($d)
};

(:~
 : Refresh the version index of all corpora in the database (TEMPORARY)
 :)
declare
  %rest:POST
  %rest:path("/v1/id-index/refresh")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function refresh:refresh() {
  let $state := doc($resolver:versions-root || "/" || $refresh:state-name)
  let $last := $state/refresh/@last[. castable as xs:dateTime]!xs:dateTime(.)
  let $now := current-dateTime()
  let $elapsed := if (exists($last)) then
    refresh:seconds($now - $last)
  else (
  )
  return if (exists($elapsed) and $elapsed < $refresh:min-interval) then (
    <rest:response>
      <http:response status="503">
        <http:header
          name="Retry-After"
          value="{ xs:integer(ceiling($refresh:min-interval - $elapsed)) }" />
      </http:response>
    </rest:response>,
    map {
      "message": "The index was refreshed at " || $last || "; try again later."
    }
  ) else
    let $col := resolver:ensure-collection()
    let $stored := xmldb:store(
      $resolver:versions-root,
      $refresh:state-name,
      <refresh last="{ $now }" />
    )
    let $names :=
      for $c in
        collection($config:corpora-root)/(tei:dracorCorpus | tei:teiCorpus)
      return dutil:get-corpus-info($c)?name
    return map {
      "temporary": true(),
      "source": $resolver:default-index-source,
      "corpora":
        array
          {
            for $name in $names
            return resolver:refresh-corpus($name)
          }
    }
};

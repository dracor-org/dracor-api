xquery version "3.1";

(:~
 : DraCor ID resolver
 :
 : Resolves, depending on the `Accept` and `Accept-Profile` headers:
 :
 : - play IDs, `/id/{id}`, e.g. `/id/ger000088` (as before);
 : - corpus names, `/id/{corpusname}`, e.g. `/id/ger` (the corpus URIs of
 : dutil:corpus-uri);
 : - play versions, `/id/{id}@{commit}`, e.g. `/id/ger000088@15a6661`;
 : - corpus versions, `/id/{corpusname}@{commit}`, e.g. `/id/ger@15a6661`.
 :
 : Versions are looked up in the DraCor version index
 : (https://github.com/dracor-org/dracor-version-index), which records for every
 : commit of a corpus repository which file holds which play. The index is
 : converted to XML and stored in $resolver:versions-root by
 : resolver:load-versions (POST /v1/id-index).
 :
 : The play resolver was moved here from api.xqm (api:id-to-url) and
 : dutil:id-to-url; `/id/{id}` without a profile behaves as before.
 :)
module namespace resolver = "http://dracor.org/ns/exist/v1/resolver";

declare namespace rest = "http://exquery.org/ns/restxq";
declare namespace http = "http://expath.org/ns/http-client";
declare namespace hc = "http://expath.org/ns/http-client";
declare namespace output = "http://www.w3.org/2010/xslt-xquery-serialization";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";

(:~
 : Profile URI of documents that follow the DraCor schema, sent as
 : `Content-Profile` (W3C Content Negotiation by Profile) with corpus.xml.
 : Interim value, see dracor-org/dracor-api#434.
 :)
declare variable $resolver:dracor-schema-profile :=
  "https://dracor.org/schema.rng";

(:~
 : Profile URI that asks for the view of a resource in its repository (e.g. the
 : corpus repository on GitHub) instead of the dracor.org page. Requested with
 : `Accept-Profile: <https://dracor.org/profiles/repository>`. Placeholder,
 : see dracor-org/dracor-api#434.
 :)
declare variable $resolver:repository-profile :=
  "https://dracor.org/profiles/repository";

(:~
 : Profile URI of the version record for the CLARIN Digital Object Gateway
 : (DOG): with it, a versioned request always gets the JSON version record or
 : a JSON error, never a redirect. Placeholder, see dracor-org/dracor-api#434.
 :)
declare variable $resolver:dog-profile := "https://dracor.org/profiles/dog";

(: Media types for which XML (corpus.xml, TEI) is returned :)
declare variable $resolver:xml-types := (
  "application/tei+xml", "application/xml"
);

(: Collection holding one document per corpus converted from the index :)
declare variable $resolver:versions-root := $config:dracor-root || "/versions";

(: Default location of the version index (one folder per corpus) :)
declare variable $resolver:default-index-source :=
  "https://raw.githubusercontent.com/dracor-org/dracor-version-index/main/index";

(:~
 : Earlier ID prefixes, not derivable from the index files (the index keys
 : plays by their current ID). Same as HISTORIC_PREFIXES in the index's
 : archaeology.py.
 :)
declare variable $resolver:former-prefixes := map {"eng": ("ep")};

(: ===================================================================== :)
(: Endpoint :)
(: ===================================================================== :)

(:~
 : Resolve a DraCor ID, a corpus name, or a version of either
 :
 : Play (`/id/{id}`): depending on `Accept`, redirects to the JSON metadata
 : (`application/json`), the RDF (`application/rdf+xml`) or, for any other
 : value, the dracor.org page of the play. With the repository profile, the
 : page view goes to the file in the corpus repository instead.
 :
 : Corpus (`/id/{corpusname}`): redirects to the JSON of the corpus
 : (`application/json`) or the corpus page; `application/tei+xml` and
 : `application/xml` return the corpus.xml stored in the database (200). With
 : the repository profile, the page view goes to the corpus repository.
 :
 : Versions (`…@{commit}`, or `…:{commit}`): see
 : resolver:resolve-play-version and resolver:resolve-corpus-version. `:` is
 : accepted as an alternative separator so that a handle extension
 : (`PREFIX/SUFFIX@als000001:bc1e1e8`) needs only one `@`. `@` is the
 : canonical form under `/id/`.
 :
 : @param $id DraCor ID or corpus name, optionally followed by `@{commit}`
 : or `:{commit}`
 : @param $accept Accept header value
 : @param $profile Accept-Profile header value
 : @result redirect, XML, JSON or error
 :)
declare
  %rest:GET
  %rest:path("/v1/id/{$id}")
  %rest:header-param("Accept", "{$accept}")
  %rest:header-param("Accept-Profile", "{$profile}")
function resolver:resolve($id, $accept, $profile) {
  let $sep := (("@", ":")[contains($id, .)])[1]
  return if ($sep) then
    resolver:resolve-version(
      substring-before($id, $sep),
      substring-after($id, $sep),
      $accept,
      $profile
    )
  else
    resolver:resolve-current($id, $accept, $profile)
};

(:~
 : Resolve the resolver base `/id`, with or without the `id` parameter
 :
 : `/id?id={id}` and `/id?id={id}@{commit}` resolve exactly like `/id/{id}`
 : and `/id/{id}@{commit}`.
 :
 : This is meant for a single handle for all of DraCor. GWDG's handle
 : template (delimiter `@`, target `${data}?${extension}`) turns
 : `PREFIX/SUFFIX@ger000088@15a6661` into `{target}?ger000088@15a6661`.
 : RESTXQ only passes query parameters by name and has no access to the raw
 : query string, so the handle points to `https://dracor.org/id?id=`; the
 : template then yields `https://dracor.org/id?id=?ger000088@15a6661`, and
 : the leading `?` of the value is dropped here.
 :
 : Without a value, it redirects to the DraCor front page, or with
 : `Accept: application/json` to the API info, so the bare handle still lands
 : somewhere useful.
 :
 : RESTXQ cannot register `/v1/id/` (trailing slash); that has to be handled
 : by the proxy.
 :
 : @param $id-param DraCor ID or corpus name, optionally with `@{commit}`
 : @param $accept Accept header value
 : @param $profile Accept-Profile header value
 : @result redirect, XML, JSON or error
 :)
declare
  %rest:GET
  %rest:path("/v1/id")
  %rest:query-param("id", "{$id-param}")
  %rest:header-param("Accept", "{$accept}")
  %rest:header-param("Accept-Profile", "{$profile}")
function resolver:resolve-base($id-param, $accept, $profile) {
  let $id := replace(string($id-param[1]), "^\?", "") => normalize-space()
  return if ($id) then
    resolver:resolve($id, $accept, $profile)
  else
    resolver:redirect(
      if ($accept = "application/json") then
        $config:api-base || "/info"
      else
        $config:api-origin || "/"
    )
};

(:~
 : Resolve a play ID or corpus name without a version
 :)
declare function resolver:resolve-current(
  $id as xs:string,
  $accept as xs:string*,
  $profile as xs:string*
) {
  let $tei := dutil:get-play-by-id($id)
  let $corpus := if ($tei) then (
  ) else
    dutil:get-corpus($id)[1]
  let $xml-type := $resolver:xml-types[. = $accept][1]
  let $wants-repository := not(
    $accept = ("application/json", "application/rdf+xml")
  ) and
    resolver:requests-profile($profile, $resolver:repository-profile)

  return if ($tei and $wants-repository) then
    resolver:redirect(resolver:play-repository-url($tei))
  else if ($tei) then
    resolver:redirect(resolver:id-to-url($id, $accept))
  else if ($corpus and $xml-type) then
    resolver:corpus-xml($corpus, $xml-type)
  else if ($corpus and $wants-repository) then
    resolver:redirect(dutil:get-corpus-info($corpus)?repository)
  else if ($corpus) then
    resolver:redirect(resolver:corpus-to-url($id, $accept))
  else
    <rest:response><http:response status="404" /></rest:response>
};

(:~
 : Resolve `{id}@{commit}` or `{corpusname}@{commit}`
 :)
declare function resolver:resolve-version(
  $id as xs:string,
  $commit as xs:string,
  $accept as xs:string*,
  $profile as xs:string*
) {
  let $dog := resolver:requests-profile($profile, $resolver:dog-profile)
  let $is-play := matches($id, "^[a-z]+[0-9]+$")

  return if (not(matches($commit, "^[0-9a-fA-F]{7,40}$"))) then
    resolver:error(
      400,
      "bad-request",
      "'" ||
        $commit ||
        "' is not a commit hash (7 to 40 hexadecimal characters).",
      $dog
    )
  else if (not(matches($id, "^[a-z]+[0-9]*$"))) then
    resolver:error(
      400,
      "bad-request",
      "'" || $id || "' is neither a DraCor play ID nor a corpus name.",
      $dog
    )
  else
    let $versions := if ($is-play) then
      resolver:versions-by-prefix(replace($id, "[0-9]+$", ""))
    else
      resolver:versions-by-corpus($id)
    (:
     : The commit DraCor has loaded may be newer than the index (the index is
     : updated nightly, a corpus is loaded on push). It resolves like
     : `/id/{id}` even if the index does not know it yet; the DOG profile
     : still needs the index for its record.
     :)
    let $loaded-sha := resolver:loaded-commit($id, $is-play)
    let $is-loaded := not($dog) and
      string-length($commit) >= 7 and
      starts-with($loaded-sha, lower-case($commit))
    let $in-index := exists($versions!resolver:find-commit(., $commit))

    return if ($is-loaded and not($in-index)) then
      resolver:resolve-current($id, $accept, $profile)
    else if (not($versions)) then
      resolver:error(
        404,
        "unknown-corpus",
        if ($is-play) then
          "No corpus in the version index has the ID prefix '" ||
            replace($id, "[0-9]+$", "") ||
            "'."
        else
          "The version index has no corpus '" || $id || "'.",
        $dog
      )
    else
      let $commits := resolver:find-commit($versions, $commit)

      return if (count($commits) = 0) then
        resolver:error(
          404,
          "unknown-commit",
          "Commit " ||
            $commit ||
            " is not in the version index of corpus " ||
            $versions/@corpus ||
            " (index up to " ||
            substring($versions/@head, 1, 7) ||
            ", " ||
            substring($versions/@head-date, 1, 10) ||
            "). It may be newer than the index.",
          $dog
        )
      else if (count($commits) > 1) then
        resolver:error(
          404,
          "ambiguous-commit",
          "The abbreviation " ||
            $commit ||
            " fits " ||
            count($commits) ||
            " commits of corpus " ||
            $versions/@corpus ||
            "; use a longer hash.",
          $dog
        )
      else if ($is-play) then
        resolver:resolve-play-version(
          $versions,
          $commits,
          $id,
          $accept,
          $profile
        )
      else
        resolver:resolve-corpus-version($versions, $commits, $accept, $profile)
};

(:~
 : The commit DraCor has loaded for a play or corpus (empty if not loaded)
 :
 : @param $id DraCor ID or corpus name
 : @param $is-play true for a play ID
 :)
declare function resolver:loaded-commit(
  $id as xs:string,
  $is-play as xs:boolean
) as xs:string? {
  if ($is-play) then
    let $tei := dutil:get-play-by-id($id)
    return if ($tei) then
      doc(dutil:filepaths(base-uri($tei))?files?git)/git/sha/string()
    else (
    )
  else
    dutil:get-corpus-info-by-name($id)?commit
};

(:~
 : Respond to a resolved play version
 :
 : - DOG profile: 200 and the version record, always.
 : - The commit DraCor has loaded for the play: the same as `/id/{id}`.
 : - Other commits: `application/json` 200 and the version record;
 : `application/tei+xml`/`application/xml` 303 to the raw file on GitHub;
 : `application/rdf+xml` 406; anything else 303 to the file on GitHub.
 :)
declare function resolver:resolve-play-version(
  $versions as element(versions),
  $commit as element(commit),
  $id as xs:string,
  $accept as xs:string*,
  $profile as xs:string*
) {
  let $dog := resolver:requests-profile($profile, $resolver:dog-profile)
  let $files := resolver:files-at($versions, $commit, $id)

  return if (count($files) = 0) then
    resolver:error(
      404,
      "not-found",
      "No file of corpus " ||
        $versions/@corpus ||
        " carries the ID " ||
        $id ||
        " at commit " ||
        substring($commit/@sha, 1, 7) ||
        ".",
      $dog
    )
  else if (count($files) > 1) then
    resolver:respond(
      300,
      map {
        "status": 300,
        "error": "duplicate-id",
        "message":
          count($files) ||
            " files carry the ID " ||
            $id ||
            " at commit " ||
            substring($commit/@sha, 1, 7) ||
            ".",
        "files":
          array
            {
              for $f in $files
              return resolver:play-record($versions, $commit, $id, $f)
            }
      },
      $dog
    )
  else
    let $record := resolver:play-record($versions, $commit, $id, $files)

    return if ($dog) then
      resolver:respond(200, $record, true())
    else if ($record?loaded) then
      resolver:resolve-current($id, $accept, $profile)
    else if ($accept = "application/json") then
      resolver:respond(200, $record, false())
    else if ($accept = $resolver:xml-types) then
      resolver:redirect($record?urls?raw)
    else if ($accept = "application/rdf+xml") then
      resolver:error(
        406,
        "not-acceptable",
        "There is no RDF for versions other than the one DraCor has loaded.",
        false()
      )
    else
      resolver:redirect($record?urls?github)
};

(:~
 : Respond to a resolved corpus version
 :
 : - DOG profile: 200 and the corpus version record.
 : - The commit DraCor has loaded for the corpus: the same as
 : `/id/{corpusname}`.
 : - Other commits: `application/json` 200 and the corpus version record;
 : `application/tei+xml`/`application/xml` 303 to the raw corpus.xml at
 : that commit; anything else 303 to the repository at that commit.
 :)
declare function resolver:resolve-corpus-version(
  $versions as element(versions),
  $commit as element(commit),
  $accept as xs:string*,
  $profile as xs:string*
) {
  let $dog := resolver:requests-profile($profile, $resolver:dog-profile)
  let $name := $versions/@corpus/string()
  let $sha := $commit/@sha/string()
  let $loaded := dutil:get-corpus-info-by-name($name)?commit = $sha
  let $repo := $versions/@repository/string()
  let $record := map {
    "corpus": $name,
    "commit": $sha,
    "date": $commit/@date/string(),
    "loaded": $loaded,
    "license": resolver:license($versions),
    "urls":
      map {
        "github": $repo || "/tree/" || $sha,
        "raw": resolver:raw-url($repo, $sha, "corpus.xml")
      }
  }

  return if ($dog) then
    resolver:respond(200, $record, true())
  else if ($loaded) then
    resolver:resolve-current($name, $accept, $profile)
  else if ($accept = "application/json") then
    resolver:respond(200, $record, false())
  else if ($accept = $resolver:xml-types) then
    resolver:redirect($record?urls?raw)
  else
    resolver:redirect($record?urls?github)
};

(: ===================================================================== :)
(: Lookup in the version index :)
(: ===================================================================== :)

declare function resolver:versions-by-prefix(
  $prefix as xs:string
) as element(versions)? {
  collection($resolver:versions-root)/versions[prefix = $prefix][1]
};

declare function resolver:versions-by-corpus(
  $name as xs:string
) as element(versions)? {
  collection($resolver:versions-root)/versions[@corpus = $name][1]
};

(:~
 : Commits matching a full or abbreviated hash
 :)
declare function resolver:find-commit(
  $versions as element(versions),
  $commit as xs:string
) as element(commit)* {
  let $c := lower-case($commit)
  return if (string-length($c) = 40) then
    $versions/commit[@sha = $c]
  else
    $versions/commit[starts-with(@sha, $c)]
};

(:~
 : Files carrying the ID $id at $commit, as maps with path, blob, key,
 : id_in_file and id_method
 :
 : Main-line commit: the intervals valid at its seq. Side-branch commit: the
 : files at its base_seq, changed by its own A/M/D rows. Rows whose key is
 : $id win; if there are none, rows whose id_in_file is $id.
 :)
declare function resolver:files-at(
  $versions as element(versions),
  $commit as element(commit),
  $id as xs:string
) as map(*)* {
  let $side := not($commit/@seq)
  let $seq := xs:integer(($commit/@seq, $commit/@base)[1])
  let $changes := if ($side) then
    $versions/change[@commit = $commit/@sha]
  else (
  )
  let $by-key := (
    resolver:valid-at($versions/file[@key = $id], $seq)[not(
      @path = $changes/@path
    )],
    $changes[@type = ("A", "M")][@key = $id]
  )
  let $rows := if ($by-key) then
    $by-key
  else (
    resolver:valid-at($versions/file[@id-in-file = $id], $seq)[not(
      @path = $changes/@path
    )],
    $changes[@type = ("A", "M")][@id-in-file = $id]
  )

  for $r in $rows
  return map {
    "path": $r/@path/string(),
    "blob": $r/@blob/string(),
    "key": $r/@key/string(),
    "id_in_file": $r/@id-in-file[normalize-space()]/string(),
    "id_method": $r/@id-method[normalize-space()]/string()
  }
};

declare function resolver:valid-at(
  $files as element(file)*,
  $seq as xs:integer
) as element(file)* {
  $files[xs:integer(@from) le $seq][not(@to) or xs:integer(@to) ge $seq]
};

(:~
 : Version record of a play (RESOLVER.md 4.3 in the version index)
 :)
declare function resolver:play-record(
  $versions as element(versions),
  $commit as element(commit),
  $id as xs:string,
  $file as map(*)
) as map(*) {
  let $sha := $commit/@sha/string()
  let $repo := $versions/@repository/string()
  let $tei := dutil:get-play-by-id($id)
  let $paths := if ($tei) then
    dutil:filepaths(base-uri($tei))
  else (
  )
  let $loaded-sha := if ($tei) then
    doc($paths?files?git)/git/sha/string()
  else (
  )
  let $loaded := $paths?corpusname = $versions/@corpus and $loaded-sha = $sha

  return map:merge(
    (
      map {
        "id": $id,
        "corpus": $versions/@corpus/string(),
        "commit": $sha,
        "date": $commit/@date/string(),
        "path": $file?path,
        "blob": $file?blob,
        "id_in_file": $file?id_in_file,
        "id_method": $file?id_method,
        "loaded": $loaded,
        "license": resolver:license($versions),
        "urls":
          map:merge(
            (
              map {
                "github": $repo || "/blob/" || $sha || "/" || $file?path,
                "raw": resolver:raw-url($repo, $sha, $file?path)
              },
              if ($loaded) then
                map {
                  "api":
                    $config:api-base ||
                      "/corpora/" ||
                      $paths?corpusname ||
                      "/plays/" ||
                      $paths?playname,
                  "page":
                    $config:api-origin ||
                      "/" ||
                      $paths?corpusname ||
                      "/" ||
                      $paths?playname
                }
              else (
              )
            )
          )
      }
    )
  )
};

declare function resolver:license($versions as element(versions)) {
  let $l := $versions/license
  return if ($l) then
    map {"name": $l/@name/string(), "url": $l/@url/string()}
  else (
  )
};

(:~
 : raw.githubusercontent.com URL of a file at a commit
 :)
declare function resolver:raw-url(
  $repo as xs:string,
  $sha as xs:string,
  $path as xs:string
) as xs:string {
  replace(
    $repo,
    "^https://github\.com/",
    "https://raw.githubusercontent.com/"
  ) ||
    "/" ||
    $sha ||
    "/" ||
    $path
};

(: ===================================================================== :)
(: Responses :)
(: ===================================================================== :)

(:~
 : Whether an Accept-Profile header value lists the profile $uri
 :
 : @param $header Accept-Profile header value(s), e.g. `<https://…>;q=0.5, <…>`
 : @param $uri Profile URI
 :)
declare function resolver:requests-profile(
  $header as xs:string*,
  $uri as xs:string
) as xs:boolean {
  some $h in $header satisfies contains($h, "<" || $uri || ">")
};

(:~
 : 303 redirect to $url
 :)
declare function resolver:redirect($url as xs:string) {
  <rest:response>
    <http:response status="303">
      <http:header name="location" value="{ $url }" />
    </http:response>
  </rest:response>
};

(:~
 : JSON response; with $dog, it names the DOG profile in Content-Profile
 :)
declare function resolver:respond(
  $status as xs:integer,
  $body as map(*),
  $dog as xs:boolean
) {
  <rest:response>
    <output:serialization-parameters>
      <output:method value="json" />
    </output:serialization-parameters>
    <http:response status="{ $status }">
      <http:header name="Content-Type" value="application/json" />
      {
        if ($dog) then
          <http:header
            name="Content-Profile"
            value="&lt;{ $resolver:dog-profile }&gt;" />
        else (
        )
      }
      <http:header name="Vary" value="Accept, Accept-Profile" />
    </http:response>
  </rest:response>,
  $body
};

declare function resolver:error(
  $status as xs:integer,
  $error as xs:string,
  $message as xs:string,
  $dog as xs:boolean
) {
  resolver:respond(
    $status,
    map {"status": $status, "error": $error, "message": $message},
    $dog
  )
};

(:~
 : Return the corpus.xml of a corpus as stored in the database
 :
 : @param $corpus dracorCorpus (or legacy teiCorpus) element
 : @param $media-type Media type of the response
 :)
declare function resolver:corpus-xml(
  $corpus as element(),
  $media-type as xs:string
) {
  <rest:response>
    <output:serialization-parameters>
      <output:method value="xml" />
    </output:serialization-parameters>
    <http:response status="200">
      <http:header name="Content-Type" value="{ $media-type }" />
      <http:header
        name="Content-Profile"
        value="&lt;{ $resolver:dracor-schema-profile }&gt;" />
      <http:header name="Vary" value="Accept, Accept-Profile" />
    </http:response>
  </rest:response>,
  $corpus
};

(:~
 : Translate DraCor ID to URL
 :
 : @param $id DraCor ID
 : @param $accept MIME type
 :)
declare function resolver:id-to-url($id as xs:string, $accept as xs:string*) {
  let $tei := dutil:get-play-by-id($id)

  return if ($tei) then
    let $paths := dutil:filepaths(base-uri($tei))
    let $corpus := $paths?corpusname
    let $play := $paths?playname
    let $url := $config:api-base || "/corpora/" || $corpus || "/plays/" || $play

    return if ($accept = "application/json") then
      $url
    else if ($accept = "application/rdf+xml") then
      $url || "/rdf"
    else
      $config:api-origin || "/" || $corpus || "/" || $play
  else (
  )
};

(:~
 : URL of the TEI file of a loaded play in its corpus repository, at the
 : commit it was loaded from
 :)
declare function resolver:play-repository-url($tei as element()) as xs:string {
  let $paths := dutil:filepaths(base-uri($tei))
  let $repo := dutil:get-corpus-info-by-name($paths?corpusname)?repository
  let $sha := doc($paths?files?git)/git/sha/string()
  return $repo ||
    "/blob/" ||
    ($sha[.], "HEAD")[1] ||
    "/tei/" ||
    $paths?playname ||
    ".xml"
};

(:~
 : Translate corpus name to URL
 :
 : @param $corpusname Name of the corpus
 : @param $accept MIME type
 :)
declare function resolver:corpus-to-url(
  $corpusname as xs:string,
  $accept as xs:string*
) {
  if ($accept = "application/json") then
    $config:api-base || "/corpora/" || $corpusname
  else
    $config:api-origin || "/" || $corpusname
};

(: ===================================================================== :)
(: Loading the version index :)
(: ===================================================================== :)

(:~
 : Load the version index into the database
 :
 : Fetches commits.csv, components.csv, side_commits.csv and meta.json of
 : each corpus (and registry.json for licences) from $source, converts them
 : to one XML document per corpus and stores it in $resolver:versions-root.
 : Only TEI rows (kind `tei` and `tei-unresolved`) are kept.
 :
 : Requires authorization.
 :
 : @param $corpora Corpus names, comma separated (default: all corpora in the
 : database)
 : @param $source Base URL of the index (default: $resolver:default-index-source)
 : @param $auth Authorization header value
 :)
declare
  %rest:POST
  %rest:path("/v1/id-index")
  %rest:query-param("corpora", "{$corpora}")
  %rest:query-param("source", "{$source}")
  %rest:header-param("Authorization", "{$auth}")
  %rest:produces("application/json")
  %output:media-type("application/json")
  %output:method("json")
function resolver:post-index($corpora, $source, $auth) {
  if (not(exists($auth) and sm:id()//sm:real/sm:username ne "guest")) then (
    <rest:response><http:response status="401" /></rest:response>,
    map {"message": "authorization required"}
  ) else
    let $base := replace(
      ($source[normalize-space()], $resolver:default-index-source)[1],
      "/+$",
      ""
    )
    let $names := if ($corpora[normalize-space()]) then
      tokenize(string-join($corpora, ","), "\s*,\s*")[.]
    else
      for $c in
        collection($config:corpora-root)/(tei:dracorCorpus | tei:teiCorpus)
      return dutil:get-corpus-info($c)?name
    let $registry := try {
      resolver:fetch-json($base || "/registry.json")
    } catch * { () }
    return array
      {
        for $name in $names
        return try { resolver:load-versions($name, $base, $registry) } catch * {
          map {"corpus": $name, "error": $err:description}
        }
      }
};

(:~
 : Load the version index of one corpus from the default source
 :
 : Called by the corpus load jobs (jobs/load-corpus.xq,
 : jobs/process-webhook-delivery.xq), so the index is refreshed whenever a
 : corpus is loaded or updated, without an endpoint of its own. The source
 : is fixed ($resolver:default-index-source). Never raises an error: a
 : failure is logged and returned, so it cannot break the corpus load.
 :
 : @param $name Corpus name
 : @return summary map, or a map with `error`
 :)
declare function resolver:refresh-corpus($name as xs:string?) as map(*) {
  if (not($name)) then
    map {"error": "no corpus name"}
  else
    try {
      let $registry := try {
        resolver:fetch-json($resolver:default-index-source || "/registry.json")
      } catch * { () }
      let $result := resolver:load-versions(
        $name,
        $resolver:default-index-source,
        $registry
      )
      return (util:log-system-out("version index loaded: " || $name), $result)
    } catch * {
      util:log-system-out(
        "version index not loaded for " || $name || ": " || $err:description
      ),
      map {"corpus": $name, "error": $err:description}
    }
};

declare function resolver:load-versions(
  $name as xs:string,
  $base as xs:string,
  $registry as map(*)?
) as map(*) {
  let $dir := $base || "/" || $name
  let $meta := resolver:fetch-json($dir || "/meta.json")
  let $commits := resolver:csv(resolver:fetch-text($dir || "/commits.csv"))
  let $files := resolver:csv(resolver:fetch-text($dir || "/components.csv"))
  let $changes := resolver:csv(resolver:fetch-text($dir || "/side_commits.csv"))
  let $prefix := ($meta?id_archaeology?prefix, $name)[1]
  let $licence := array:flatten($registry?corpora)[?name = $name]?license
  let $tei := ("tei", "tei-unresolved")
  let $head-date := $commits[?commit = $meta?head]?date
  let $doc := <versions
    corpus="{ $name }"
    head="{ $meta?head }"
    head-date="{ $head-date }"
    loaded="{ current-dateTime() }"
    repository="{
      replace(replace($meta?repository, "#.*$", ""), "\.git$", "")
    }"
    source="{ $dir }"
  >
    <prefix>{ $prefix }</prefix>
    {
      for $p in $resolver:former-prefixes($name)
      return <prefix former="true">{ $p }</prefix>,
      if (exists($licence)) then
        <license name="{ $licence?name }" url="{ $licence?url }" />
      else (
      ),
      for $c in $commits
      return <commit date="{ $c?date }" sha="{ $c?commit }">
        {
          if ($c?seq) then
            attribute seq { $c?seq }
          else
            attribute base { $c?base_seq }
        }
      </commit>,
      for $f in $files[?kind = $tei]
      return <file
        blob="{ $f?blob }"
        from="{ $f?from_seq }"
        id-in-file="{ $f?id_in_file }"
        id-method="{ $f?id_method }"
        key="{ $f?key }"
        path="{ $f?path }"
      >
        {
          if ($f?to_seq) then
            attribute to { $f?to_seq }
          else (
          )
        }
      </file>,
      for $s in $changes[?kind = $tei]
      return <change
        blob="{ $s?blob }"
        commit="{ $s?commit }"
        id-in-file="{ $s?id_in_file }"
        id-method="{ $s?id_method }"
        key="{ $s?key }"
        path="{ $s?path }"
        type="{ $s?change }" />
    }
  </versions>
  let $stored := (
    resolver:ensure-collection(),
    xmldb:store($resolver:versions-root, $name || ".xml", $doc)
  )
  return map {
    "corpus": $name,
    "prefix": $prefix,
    "commits": count($doc/commit),
    "files": count($doc/file),
    "changes": count($doc/change),
    "head": $meta?head
  }
};

(:~
 : Create the versions collection and its range index configuration
 :)
declare function resolver:ensure-collection() {
  if (xmldb:collection-available($resolver:versions-root)) then (
  ) else
    let $conf := "/db/system/config" || $resolver:versions-root
    return (
      resolver:mkcol("/db/system/config", $resolver:versions-root),
      xmldb:store(
        $conf,
        "collection.xconf",
        <collection xmlns="http://exist-db.org/collection-config/1.0">
          <index>
            <range>
              <create qname="@sha" type="xs:string" />
              <create qname="@key" type="xs:string" />
              <create qname="@id-in-file" type="xs:string" />
              <create qname="@commit" type="xs:string" />
              <create qname="@corpus" type="xs:string" />
              <create qname="prefix" type="xs:string" />
            </range>
          </index>
        </collection>
      ),
      resolver:mkcol("", $resolver:versions-root)
    )
};

(:~
 : Create $path (e.g. /db/dracor/versions) below $parent, segment by segment
 :)
declare function resolver:mkcol($parent as xs:string, $path as xs:string) {
  fold-left(
    tokenize($path, "/")[.],
    $parent,
    function ($col, $segment) {
      let $new := $col || "/" || $segment
      return (
        if (xmldb:collection-available($new)) then (
        ) else
          xmldb:create-collection(
            if ($col) then
              $col
            else
              "/",
            $segment
          ),
        $new
      )[last()]
    }
  )
};

declare function resolver:fetch-text($url as xs:string) as xs:string {
  (: fetch as binary and decode as UTF-8, whatever charset the server names :)
  let $response := hc:send-request(
    <hc:request
      href="{ $url }"
      method="get"
      override-media-type="application/octet-stream" />
  )
  return if ($response[1]/@status = "200") then
    util:binary-to-string($response[2], "UTF-8")
  else
    error(
      xs:QName("resolver:fetch"),
      "GET " || $url || " returned " || $response[1]/@status
    )
};

declare function resolver:fetch-json($url as xs:string) as map(*)? {
  parse-json(resolver:fetch-text($url))
};

(:~
 : Parse CSV without quoted fields (the index writes none) into maps keyed by
 : the header row
 :)
declare function resolver:csv($text as xs:string) as map(*)* {
  let $lines := tokenize($text, "\r?\n")[normalize-space()]
  let $head := tokenize($lines[1], ",")
  for $line in tail($lines)
  let $fields := tokenize($line, ",")
  return map:merge(
    for $i in 1 to count($head)
    return map:entry($head[$i], ($fields[$i], "")[1])
  )
};

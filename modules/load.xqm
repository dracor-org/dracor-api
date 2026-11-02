xquery version "3.1";

(:~
 : Module providing function to load files from zip archives.
 :
 : Loading a corpus only replaces the TEI documents that have changed and
 : removes the plays that are no longer part of the archive. Every write
 : keeps eXist-db from answering any other query while it lasts, so a reload
 : of a corpus with few changes should write as little as possible.
 :
 : To tell whether a TEI document has changed, the git.xml file of a play
 : records the hash of the document in the archive it was loaded from, and the
 : modification time of the stored tei.xml. If either differs, e.g. because the
 : play has been updated through a webhook or the API since, the document is
 : replaced.
 :)
module namespace load = "http://dracor.org/ns/exist/v1/load";

declare namespace compression = "http://exist-db.org/xquery/compression";
declare namespace util = "http://exist-db.org/xquery/util";
declare namespace tei = "http://www.tei-c.org/ns/1.0";

import module namespace config = "http://dracor.org/ns/exist/v1/config" at "config.xqm";
import module namespace metrics = "http://dracor.org/ns/exist/v1/metrics" at "metrics.xqm";
import module namespace dutil = "http://dracor.org/ns/exist/v1/util" at "util.xqm";
import module namespace gh = "http://dracor.org/ns/exist/v1/github" at "github.xqm";
import module namespace drdf = "http://dracor.org/ns/exist/v1/rdf" at "rdf.xqm";

(: files of a play collection; anything else is removed when loading :)
declare variable $load:play-files := (
  "tei.xml", "git.xml", "metrics.xml", "rdf.xml", "sitelinks.xml", "sync.xml"
);

(: files of a corpus collection besides the play collections :)
declare variable $load:corpus-files := ("corpus.xml", "git.xml");

(:~
 : Remove all files and collections of a collection except the given files
 :
 : @param $collection Path of the collection
 : @param $keep Names of the files to keep
 : @param $keep-collections Names of the collections to keep
 : @return Paths of the removed files and collections
 :)
declare function local:remove-others(
  $collection as xs:string,
  $keep as xs:string*,
  $keep-collections as xs:string*
) as xs:string* {
  for $resource in xmldb:get-child-resources($collection)[not(. = $keep)]
  let $path := $collection || "/" || $resource
  return (
    util:log-system-out("Removing " || $path),
    xmldb:remove($collection, $resource),
    $path
  ),
  for $child in
    xmldb:get-child-collections($collection)[not(. = $keep-collections)]
  let $path := $collection || "/" || $child
  return (util:log-system-out("Removing " || $path), xmldb:remove($path), $path)
};

(:~
 : Store a TEI document from the archive unless it is unchanged
 :
 : @param $collection Path of the corpus collection
 : @param $name Play name
 : @param $data TEI document
 : @param $sha Git SHA of the archive
 : @return play element with the play name and the action taken
 :)
declare function local:update-play(
  $collection as xs:string,
  $name as xs:string,
  $data as document-node(),
  $sha as xs:string?
) as element(play) {
  let $play-collection := $collection || "/" || $name
  let $hash := util:hash(serialize($data), "SHA-256")
  let $git := doc($play-collection || "/git.xml")/git
  let $unchanged := if (
    $git/source/@hash = $hash and doc-available($play-collection || "/tei.xml")
  ) then
    xs:dateTime($git/source/@tei-modified) =
      xmldb:last-modified($play-collection, "tei.xml")
  else
    false()

  return try {
    let $modified := if ($unchanged) then
      xs:dateTime($git/source/@tei-modified)
    else
      let $log := util:log-system-out("Storing " || $play-collection)
      let $col := xmldb:create-collection($collection, $name)
      let $stored := xmldb:store($col, "tei.xml", $data)
      return xmldb:last-modified($col, "tei.xml")
    let $new-git := <git>
      {
        if ($sha) then
          <sha>{ $sha }</sha>
        else (
        )
      }
      <source hash="{ $hash }" tei-modified="{ $modified }" />
    </git>
    let $recorded := if (deep-equal($git, $new-git)) then (
    ) else
      xmldb:store($play-collection, "git.xml", $new-git)
    let $removed := local:remove-others($play-collection, $load:play-files, ())
    return <play
      action="{
        if ($unchanged) then
          "unchanged"
        else
          "stored"
      }"
      name="{ $name }" />
  } catch * {
    util:log-system-out($err:description),
    <play action="failed" name="{ $name }" />
  }
};

(:~
 : Store corpus.xml from the archive unless it is unchanged
 :
 : @param $collection Path of the corpus collection
 : @param $data corpus.xml document
 :)
declare function local:update-corpus-xml(
  $collection as xs:string,
  $data as document-node()
) as empty-sequence() {
  if (deep-equal(doc($collection || "/corpus.xml")/*, $data/*)) then (
  ) else
    let $stored := xmldb:store($collection, "corpus.xml", $data)
    return ()
};

declare function local:entry-data(
  $path as xs:anyURI,
  $type as xs:string,
  $data as item()?,
  $param as item()*
) as element(play)? {
  if ($data) then
    let $collection := $param[1]
    let $sha := $param[2]
    let $filename := tokenize($path, "/")[last()]
    let $name := replace($filename, "\.xml$", "")
    let $log := util:log-system-out("LOADING " || $path)
    return if (
      $name = "corpus" and $data/(tei:teiCorpus | tei:dracorCorpus)
    ) then
      local:update-corpus-xml($collection, $data)
    else if (not($data/tei:TEI)) then
      util:log-system-out("Skipping non-TEI document: " || $path)
    else
      local:update-play($collection, $name, $data, $sha)
  else (
  )
};

declare function local:entry-filter(
  $path as xs:anyURI,
  $type as xs:string,
  $param as item()*
) as xs:boolean {
  (: filter paths using only corpus.xml or files in the "tei" subdirectory :)
  if (
    $type eq "resource" and
      (contains($path, "/tei/") or contains($path, "corpus.xml"))
  ) then
    true()
  else
    false()
};

declare function local:record-corpus-sha($name) {
  let $sha := dutil:get-corpus-sha($name)
  return if ($sha) then
    dutil:record-sha($name, $sha)
  else
    dutil:remove-corpus-sha($name)
};

(:~
 : Load corpus from ZIP archive
 :
 : @param $corpus The <dracorCorpus> element providing corpus name and archive URL
 : @return Log messages
 :
 : NB: until we remove support for it in v2 $corpus can also be a <teiCorpus>
 : element
 :)
declare function load:load-corpus($corpus as element()) as xs:string* {
  let $info := dutil:get-corpus-info($corpus)
  let $name := $info?name

  let $corpus-collection := $config:corpora-root || "/" || $name

  let $archive := if ($info?archive) then
    map {"url": $info?archive}
  else if ($info?repository) then
    gh:get-archive($info?repository)
  else (
  )

  return if (not(count($archive)) or not($archive?url)) then (
    util:log-system-out("cannot determine archive URL")
  ) else
    let $log := util:log-system-out("loading " || $archive?url)
    let $request := <hc:request href="{ $archive?url }" method="get" />
    let $response := hc:send-request($request)
    return if ($response[1]/@status = "200") then
      let $body := $response[2]
      let $zip := xs:base64Binary($body)
      (: the corpus SHA is only valid once all plays have been loaded :)
      let $removed-sha := dutil:remove-corpus-sha($name)
      (: load files from ZIP archive :)
      let $plays := compression:unzip(
        $zip,
        util:function(xs:QName("local:entry-filter"), 3),
        (),
        util:function(xs:QName("local:entry-data"), 4),
        ($corpus-collection, $archive?sha)
      )
      (: remove plays not in the archive (anymore) and any other leftovers :)
      let $removed := local:remove-others(
        $corpus-collection,
        $load:corpus-files,
        $plays/@name
      )
      return (
        local:record-corpus-sha($name),
        util:log-system-out(
          $name ||
            " LOADED: " ||
            count($plays[@action = "stored"]) ||
            " stored, " ||
            count($plays[@action = "unchanged"]) ||
            " unchanged, " ||
            count($plays[@action = "failed"]) ||
            " failed, " ||
            count($removed) ||
            " removed"
        )
      )
    else (
      util:log("warn", ("cannot load archive ", $archive?url)),
      util:log("info", $response)
    )
};

(:~
 : Update generated files for all plays in the database
 :)
declare function load:update() as xs:string* {
  metrics:update(), drdf:update-plays()
};

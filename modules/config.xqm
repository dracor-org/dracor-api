xquery version "3.1";

(:~
 : A set of helper functions to access the application context from
 : within a module.
 :)
module namespace config="http://dracor.org/ns/exist/config";

declare namespace templates="http://exist-db.org/xquery/templates";

declare namespace repo="http://exist-db.org/xquery/repo";
declare namespace expath="http://expath.org/ns/pkg";

(:
    Determine the application root collection from the current module load path.
:)
declare variable $config:app-root :=
    let $rawPath := system:get-module-load-path()
    let $modulePath :=
        (: strip the xmldb: part :)
        if (starts-with($rawPath, "xmldb:exist://")) then
            if (starts-with($rawPath, "xmldb:exist://embedded-eXist-server")) then
                substring($rawPath, 36)
            else if (starts-with($rawPath, "xmldb:exist://null")) then
                substring($rawPath, 19)
            else
                substring($rawPath, 15)
        else
            $rawPath
    return
        substring-before($modulePath, "/modules")
;

(:
  The base URL under which the REST API is hosted.

  FIXME: This should be determined dynamically using request:get-*() functions.
  However the request object doesn't seem to be available in a RESTXQ context.
:)
declare variable $config:api-base :=
  doc('/db/data/dracor/config.xml')//api-base/normalize-space();

declare variable $config:data-root := "/db/data/dracor/tei";

declare variable $config:rdf-root := "/db/data/dracor/rdf";

declare variable $config:metrics-root := "/db/data/dracor/metrics";

declare variable $config:sitelinks-root := "/db/data/dracor/sitelinks";

declare variable $config:webhook-root := "/db/data/dracor/webhook";

declare variable $config:webhook-secret :=
  doc('/db/data/dracor/secrets.xml')//gh-webhook/normalize-space();

declare variable $config:fuseki-pw :=
  doc('/db/data/dracor/secrets.xml')//fuseki/normalize-space();

(: the directory path in corpus repos where the TEI files reside :)
declare variable $config:corpus-repo-prefix := 'tei';

declare variable $config:repo-descriptor :=
  doc(concat($config:app-root, "/repo.xml"))/repo:meta;

declare variable $config:expath-descriptor :=
  doc(concat($config:app-root, "/expath-pkg.xml"))/expath:package;

declare variable $config:fuseki-server :=
  doc('/db/data/dracor/config.xml')//services/fuseki/normalize-space();

declare variable $config:metrics-server :=
  xs:anyURI(
    doc('/db/data/dracor/config.xml')//services/metrics/normalize-space()
  );

(:~
 : The Wikidata IDs for text classification currently recognized as text class
 : codes in DraCor.
 :)
declare variable $config:wd-text-classes := map {
  "Q40831": "Comedy",
  "Q80930": "Tragedy",
  "Q192881": "Tragicomedy",
  "Q1050848": "Satyr play",
  "Q131084": "Libretto"
};

(:~
 : Resolve the given path using the current application context.
 : If the app resides in the file system,
 :)
declare function config:resolve($relPath as xs:string) {
    if (starts-with($config:app-root, "/db")) then
        doc(concat($config:app-root, "/", $relPath))
    else
        doc(concat("file://", $config:app-root, "/", $relPath))
};

(:~
 : Returns the repo.xml descriptor for the current application.
 :)
declare function config:repo-descriptor() as element(repo:meta) {
    $config:repo-descriptor
};

(:~
 : Returns the expath-pkg.xml descriptor for the current application.
 :)
declare function config:expath-descriptor() as element(expath:package) {
    $config:expath-descriptor
};

declare %templates:wrap function config:app-title($node as node(), $model as map(*)) as text() {
    $config:expath-descriptor/expath:title/text()
};

declare function config:app-meta($node as node(), $model as map(*)) as element()* {
    <meta xmlns="http://www.w3.org/1999/xhtml" name="description" content="{$config:repo-descriptor/repo:description/text()}"/>,
    for $author in $config:repo-descriptor/repo:author
    return
        <meta xmlns="http://www.w3.org/1999/xhtml" name="creator" content="{$author/text()}"/>
};

(:~
 : For debugging: generates a table showing all properties defined
 : in the application descriptors.
 :)
declare function config:app-info($node as node(), $model as map(*)) {
    let $expath := config:expath-descriptor()
    let $repo := config:repo-descriptor()
    return
        <table class="app-info">
            <tr>
                <td>app collection:</td>
                <td>{$config:app-root}</td>
            </tr>
            {
                for $attr in ($expath/@*, $expath/*, $repo/*)
                return
                    <tr>
                        <td>{node-name($attr)}:</td>
                        <td>{$attr/string()}</td>
                    </tr>
            }
            <tr>
                <td>Controller:</td>
                <td>{ request:get-attribute("$exist:controller") }</td>
            </tr>
        </table>
};

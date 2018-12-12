<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
    version="1.0">
    <xsl:output method="xml"
        version="1.0"
        encoding="UTF-8"
        indent="no"/>

    <xsl:template match="@*|node()">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:copy>
    </xsl:template>

    <xsl:template match="//indexer/modules">
        <xsl:element name="modules">
            <xsl:apply-templates/>
            <xsl:element name="module">
              <xsl:attribute name="id">rdf-index</xsl:attribute>
              <xsl:attribute name="class">org.exist.indexing.rdf.TDBRDFIndex</xsl:attribute>
            </xsl:element>
        </xsl:element>
    </xsl:template>

</xsl:stylesheet>

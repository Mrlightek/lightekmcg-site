# frozen_string_literal: true

require 'erb'
require 'zip'

module LightekOffice
  class PowerpointExport
    CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.presentationml.presentation'
    PRESENTATION_NS = 'http://schemas.openxmlformats.org/presentationml/2006/main'
    DRAWING_NS = 'http://schemas.openxmlformats.org/drawingml/2006/main'
    OFFICE_RELS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    PACKAGE_RELS = 'http://schemas.openxmlformats.org/package/2006/relationships'
    CONTENT_TYPES_NS = 'http://schemas.openxmlformats.org/package/2006/content-types'
    SLIDE_NAMESPACES = %(xmlns:p="#{PRESENTATION_NS}" xmlns:a="#{DRAWING_NS}" xmlns:r="#{OFFICE_RELS}").freeze
    GROUP_PROPERTIES = '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
    COLOR_OVERRIDE = '<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>'
    COLOR_MAP = '<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'

    def self.call(content)
      new(Content.validate!('presentation', content)).build
    end

    def self.filename(title)
      "#{title.to_s.parameterize.presence || 'presentation'}.pptx"
    end

    def initialize(slides)
      @slides = slides
    end

    def build
      parts = {
        'ppt/presentation.xml' => [presentation, 'presentation.main'],
        'ppt/presProps.xml' => [%(<p:presentationPr xmlns:p="#{PRESENTATION_NS}"/>), 'presProps'],
        'ppt/slideMasters/slideMaster1.xml' => [master, 'slideMaster'],
        'ppt/slideLayouts/slideLayout1.xml' => [layout, 'slideLayout'],
        'ppt/theme/theme1.xml' => [theme, :theme]
      }
      @slides.each_with_index { |(title, body), index| parts["ppt/slides/slide#{index + 1}.xml"] = [slide(title, body), 'slide'] }

      references = {
        '_rels/.rels' => [['officeDocument', 'ppt/presentation.xml']],
        'ppt/_rels/presentation.xml.rels' => [['slideMaster', 'slideMasters/slideMaster1.xml'], ['presProps', 'presProps.xml']],
        'ppt/slideMasters/_rels/slideMaster1.xml.rels' => [['slideLayout', '../slideLayouts/slideLayout1.xml'], ['theme', '../theme/theme1.xml']],
        'ppt/slideLayouts/_rels/slideLayout1.xml.rels' => [['slideMaster', '../slideMasters/slideMaster1.xml']]
      }
      @slides.each_index do |index|
        references['ppt/_rels/presentation.xml.rels'] << ['slide', "slides/slide#{index + 1}.xml"]
        references["ppt/slides/_rels/slide#{index + 1}.xml.rels"] = [['slideLayout', '../slideLayouts/slideLayout1.xml']]
      end

      Zip::OutputStream.write_buffer do |archive|
        documents = parts.transform_values(&:first).merge(references.transform_values { |entries| relationships(entries) })
        documents.merge('[Content_Types].xml' => content_types(parts)).each do |path, xml|
          archive.put_next_entry(path)
          archive.write(%(<?xml version="1.0" encoding="UTF-8"?>\n#{xml}))
        end
      end.string
    end

    private

    def content_types(parts)
      overrides = parts.map do |path, (_, type)|
        mime = type == :theme ? 'officedocument.theme' : "officedocument.presentationml.#{type}"
        %(<Override PartName="/#{path}" ContentType="application/vnd.openxmlformats-#{mime}+xml"/>)
      end.join
      <<~XML
        <Types xmlns="#{CONTENT_TYPES_NS}">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          #{overrides}
        </Types>
      XML
    end

    def relationships(entries)
      elements = entries.each_with_index.map do |(type, target), index|
        %(<Relationship Id="rId#{index + 1}" Type="#{OFFICE_RELS}/#{type}" Target="#{target}"/>)
      end.join
      %(<Relationships xmlns="#{PACKAGE_RELS}">#{elements}</Relationships>)
    end

    def presentation
      slide_ids = @slides.each_index.map { |index| %(<p:sldId id="#{256 + index}" r:id="rId#{index + 3}"/>) }.join
      <<~XML
        <p:presentation #{SLIDE_NAMESPACES}>
          <p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>
          <p:sldIdLst>#{slide_ids}</p:sldIdLst>
          <p:sldSz cx="12192000" cy="6858000"/>
          <p:notesSz cx="6858000" cy="9144000"/>
        </p:presentation>
      XML
    end

    def master
      <<~XML
        <p:sldMaster #{SLIDE_NAMESPACES}>
          #{slide_tree}
          #{COLOR_MAP}
          <p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>
        </p:sldMaster>
      XML
    end

    def layout
      %(<p:sldLayout #{SLIDE_NAMESPACES} type="blank" preserve="1">#{slide_tree}#{COLOR_OVERRIDE}</p:sldLayout>)
    end

    def slide(title, body)
      heading = textbox(id: 2, name: 'Title', value: title, top: 500_000, height: 1_350_000, size: 3_600, bold: true)
      content = textbox(id: 3, name: 'Body', value: body, top: 2_050_000, height: 4_300_000, size: 2_400)
      %(<p:sld #{SLIDE_NAMESPACES}>#{slide_tree(heading + content)}#{COLOR_OVERRIDE}</p:sld>)
    end

    def slide_tree(shapes = '')
      "<p:cSld><p:spTree>#{GROUP_PROPERTIES}#{shapes}</p:spTree></p:cSld>"
    end

    def textbox(id:, name:, value:, top:, height:, size:, bold: false)
      paragraphs = value.split(/\r\n|\r|\n/, -1)
      paragraphs = [''] if paragraphs.empty?
      text = paragraphs.map do |line|
        cleaned = line.delete("\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF")
        %(<a:p><a:r><a:rPr lang="en-US" sz="#{size}" b="#{bold ? 1 : 0}"/><a:t>#{ERB::Util.html_escape(cleaned)}</a:t></a:r></a:p>)
      end.join
      <<~XML
        <p:sp>
          <p:nvSpPr><p:cNvPr id="#{id}" name="#{name}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr>
          <p:spPr><a:xfrm><a:off x="700000" y="#{top}"/><a:ext cx="10792000" cy="#{height}"/></a:xfrm>
            <a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr>
          <p:txBody><a:bodyPr wrap="square"><a:normAutofit/></a:bodyPr><a:lstStyle/>#{text}</p:txBody>
        </p:sp>
      XML
    end

    def theme
      palette = %w[202124 FFFFFF 343B48 F1F3F4 253975 296864 54586B 894D31 596184 46668D 0A56AA 674880]
      colors = %w[dk1 lt1 dk2 lt2 accent1 accent2 accent3 accent4 accent5 accent6 hlink folHlink].zip(palette).map do |name, hex|
        %(<a:#{name}><a:srgbClr val="#{hex}"/></a:#{name}>)
      end.join
      fonts = %w[majorFont minorFont].map do |type|
        %(<a:#{type}><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:#{type}>)
      end.join
      fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      lines = [6350, 12700, 19050].map { |width| %(<a:ln w="#{width}">#{fill}</a:ln>) }.join
      <<~XML
        <a:theme xmlns:a="#{DRAWING_NS}" name="Lightek Office"><a:themeElements>
          <a:clrScheme name="Lightek Office">#{colors}</a:clrScheme>
          <a:fontScheme name="Arial">#{fonts}</a:fontScheme>
          <a:fmtScheme name="Lightek Office">
            <a:fillStyleLst>#{fill * 3}</a:fillStyleLst>
            <a:lnStyleLst>#{lines}</a:lnStyleLst>
            <a:effectStyleLst>#{'<a:effectStyle><a:effectLst/></a:effectStyle>' * 3}</a:effectStyleLst>
            <a:bgFillStyleLst>#{fill * 3}</a:bgFillStyleLst>
          </a:fmtScheme>
        </a:themeElements></a:theme>
      XML
    end
  end
end

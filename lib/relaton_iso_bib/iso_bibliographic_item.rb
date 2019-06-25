# frozen_string_literal: false

require "nokogiri"
require "isoics"
require "deep_clone"
require "relaton_bib"
require "relaton_iso_bib/typed_title_string"
require "relaton_iso_bib/editorial_group"
require "relaton_iso_bib/xml_parser"
require "relaton_iso_bib/structured_identifier"
require "relaton_iso_bib/ics"

# Add filter method to Array.
class Array
  # @param type [String]
  # @return [Array]
  def filter(type:)
    select { |e| e.type == type }
  end
end

module RelatonIsoBib
  # Bibliographic item.
  class IsoBibliographicItem < RelatonBib::BibliographicItem
    TYPES = %w[
      standard
      international-standard technical-specification technical-report
      publicly-available-specification international-workshop-agreement guide
    ].freeze

    # @return [RelatonIsoBib::StructuredIdentifier]
    attr_reader :structuredidentifier

    # @!attribute [r] title
    #   @return [Array<RelatonIsoBib::TypedTitleString>]

    # @return [String, NilClass]
    attr_reader :doctype

    # @return [RelatonIsoBib::EditorialGroup]
    attr_reader :editorialgroup

    # @return [Array<RelatonIsoBib::Ics>]
    attr_reader :ics

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    # rubocop:disable Metrics/MethodLength, Metrics/PerceivedComplexity

    # @param edition [String]
    # @param docnumber [String, NilClass]
    # @param language [Array<String>]
    # @param script [Arrra<String>]
    # @param docstatus [RelatonBib::DocumentStatus, NilClass]
    # @param type [String, NilClass]
    # @param formattedref [RelatonBib::FormattedRef, NilClass]
    # @param version [RelatonBib::BibliographicItem::Version, NilClass]
    # @param biblionote [Array<RelatonBib::BiblioNote>]
    # @param series [Array<RelatonBib::Series>]
    # @param medium [RelatonBib::Medium, NilClas]
    # @param place [Array<String>]
    # @param extent [Array<Relaton::BibItemLocality>]
    # @param accesslocation [Array<String>]
    # @param classification [RelatonBib::Classification, NilClass]
    # @param validity [RelatonBib:Validity, NilClass]
    # @param docid [Array<RelatonBib::DocumentIdentifier>]
    # @param structuredidentifier [RelatonIsoBib::StructuredIdentifier]
    #
    # @param titles [Array<Hash>]
    # @option titles [String] :title_intro
    # @option titles [String] :title_main
    # @option titles [String] :title_part
    # @option titles [String] :language
    # @option titles [String] :script
    #
    # @param editorialgroup [Hash, RelatonIsoBib::EditorialGroup]
    # @option workgrpup [String] :name
    # @option workgrpup [String] :abbreviation
    # @option workgrpup [String] :url
    # @option workgrpup [Hash] :technical_committee
    # @option technical_committee [String] :name
    # @option technical_committee [String] :type
    # @option technical_committee [Integer] :number
    #
    # @param ics [Array<Hash>]
    # @option ics [Integer] :field
    # @option ics [Integer] :group
    # @option ics [Integer] :subgroup
    #
    # @param dates [Array<Hash>]
    # @option dates [String] :type
    # @option dates [String] :from
    # @option dates [String] :to
    #
    # @param abstract [Array<Hash>]
    # @option abstract [String] :content
    # @option abstract [String] :language
    # @option abstract [String] :script
    # @option abstract [String] :type
    #
    # @param contributors [Array<Hash>]
    # @option contributors [Hash] :entity
    # @option entity [String] :name
    # @option entity [String] :url
    # @option entity [String] :abbreviation
    # @option contributors [Array<String>] :roles
    #
    # @param copyright [Hash]
    # @option copyright [Hash] :owner
    # @option owner [String] :name
    # @option owner [String] :abbreviation
    # @option owner [String] :url
    # @option copyright [String] :from
    # @option copyright [String] :to
    #
    # @param link [Array<Hash, RelatonIsoBib::TypedUri>]
    # @option link [String] :type
    # @option link [String] :content
    #
    # @param relations [Array<Hash>]
    # @option relations [String] :type
    # @option relations [RelatonIsoBib::IsoBibliographicItem] :bibitem
    # @option relations [Array<RelatonBib::BibItemLocality>] :bib_locality
    #
    # @raise [ArgumentError]
    def initialize(**args)
      check_type args[:type]
      #check_language args.fetch(:language, [])
      #check_script args.fetch(:script, [])

      super_args = args.select do |k|
        %i[id docnumber language script docstatus dates abstract contributors
           edition version relations biblionote series medium place copyright
           link fetched docid formattedref extent accesslocation classification
           validity].include? k
      end.merge(type: "standard")
      super(super_args)

      @title = args.fetch(:titles, []).reduce([]) do |a, t|
        if t.is_a? Hash
          a + typed_titles(t)
        else
          a << t
        end
      end

      if args[:editorialgroup]
        @editorialgroup = if args[:editorialgroup].is_a?(Hash)
                            EditorialGroup.new(args[:editorialgroup])
                          else args[:editorialgroup]
                          end
      end

      @structuredidentifier = args[:structuredidentifier]
      @doctype ||= args[:type]
      @ics = args.fetch(:ics, []).map { |i| i.is_a?(Hash) ? Ics.new(i) : i }
      @link = args.fetch(:link, []).map do |s|
        s.is_a?(Hash) ? RelatonBib::TypedUri.new(s) : s
      end
      @id_attribute = true
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity
    # rubocop:enable Metrics/MethodLength, Metrics/PerceivedComplexity

    def disable_id_attribute
      @id_attribute = false
    end

    # remove title part components and abstract
    def to_all_parts
      me = DeepClone.clone(self)
      me.disable_id_attribute
      @relations << RelatonBib::DocumentRelation.new(
        type: "partOf", bibitem: me,
      )
      @language.each do |l|
        @title.delete_if { |t| t.type == "title-part" }
        ttl = @title.select { |t| t.type != "main" && t.title.language.include?(l) }
        tm_en = ttl.map { |t| t.title.content }.join " - "
        @title.detect { |t| t.type == "main" && t.title.language.include?(l) }&.title&.content = tm_en
      end
      @abstract = []
      @docidentifier.each(&:remove_part)
      @docidentifier.each(&:all_parts)
      @structuredidentifier.remove_part
      @structuredidentifier.all_parts
      @all_parts = true
    end

    # convert ISO:yyyy reference to reference to most recent
    # instance of reference, removing date-specific infomration:
    # date of publication, abstracts. Make dated reference Instance relation
    # of the redacated document
    def to_most_recent_reference
      me = DeepClone.clone(self)
      me.disable_id_attribute
      @relations << RelatonBib::DocumentRelation.new(type: "instance", bibitem: me)
      @abstract = []
      @dates = []
      @docidentifier.each &:remove_date
      @structuredidentifier&.remove_date
      @id&.sub! /-[12]\d\d\d/, ""
    end

    # @param lang [String] language code Iso639
    # @return [Array<RelatonIsoBib::TypedTitleString>]
    def title(lang: nil)
      if lang
        @title.select { |t| t.title.language.include? lang }
      else
        @title
      end
    end

    # @param type [Symbol] type of url, can be :src/:obp/:rss
    # @return [String]
    def url(type = :src)
      @link.detect { |s| s.type == type.to_s }.content.to_s
    end

    # @return [String]
    def to_xml(builder = nil, **opts, &block)
      if opts[:note]&.any?
        opts.fetch(:note, []).each do |n|
          @biblionote << RelatonBib::BiblioNote.new(
            content: n[:text], type: n[:type], format: "text/plain",
          )
        end
      end
      super builder, **opts do |b|
        if opts[:bibdata]
          b.ext do
            b.doctype doctype if doctype
            # GB renders gbcommittee elements istead of an editorialgroup element.
            if respond_to? :committee
              committee&.to_xml b
            else
              editorialgroup&.to_xml b
            end
            ics.each { |i| i.to_xml b }
            structuredidentifier&.to_xml b
            yield b if block_given?
          end
        end
      end
    end

    private

    # @param language [Array<String>]
    # @raise ArgumentError
    def check_language(language)
      language.each do |lang|
        unless %w[en fr].include? lang
          raise ArgumentError, "invalid language: #{lang}"
        end
      end
    end

    # @param script [Array<String>]
    # @raise ArgumentError
    def check_script(script)
      script.each do |scr|
        raise ArgumentError, "invalid script: #{scr}" unless scr == "Latn"
      end
    end

    # @param script [String]
    # @raise ArgumentError
    def check_type(type)
      if type && !TYPES.include?(type)
        raise ArgumentError, "invalid type: #{type}"
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/MethodLength

    # @param title [Hash]
    # @option title [String] :title_intro
    # @option title [String] :title_main
    # @option title [String] :title_part
    # @option title [String] :language
    # @option title [String] :script
    # @return [Array<RelatonIsoBib::TypedTitleStrig>]
    def typed_titles(title)
      titles = []
      if title[:title_main]
        titles << TypedTitleString.new(
          type: "title-main", content: title[:title_main],
          language: title[:language], script: title[:script], format: "text/plain",
        )
      end

      if title[:title_intro]
        titles << TypedTitleString.new(
          type: "title-intro", content: title[:title_intro],
          language: title[:language], script: title[:script], format: "text/plain",
        )
      end

      if title[:title_part]
        titles << TypedTitleString.new(
          type: "title-part", content: title[:title_part],
          language: title[:language], script: title[:script], format: "text/plain",
        )
      end

      unless titles.empty?
        titles << TypedTitleString.new(
          type: "main", content: titles.map { |t| t.title.content }.join(" - "),
          language: title[:language], script: title[:script], format: "text/plain",
        )
      end

      titles
    end

    def makeid(id, attribute, _delim = "")
      return nil if attribute && !@id_attribute

      id ||= @docidentifier.reject { |i| i&.type == "DOI" }[0]
      # contribs = publishers.map { |p| p&.entity&.abbreviation }.join '/'
      # idstr = "#{contribs}#{delim}#{id.project_number}"
      # idstr = id.project_number.to_s
      if id
        idstr = id.id
        idstr = "IEV" if structuredidentifier&.project_number == "IEV"
      else
        idstr = formattedref&.content
      end
      # if id.part_number&.size&.positive? then idstr += "-#{id.part_number}"
      idstr&.gsub(/:/, "-")&.gsub(/\s/, "")&.strip
    end
    # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  end
end

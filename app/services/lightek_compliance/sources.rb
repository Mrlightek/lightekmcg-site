require 'uri'
module LightekCompliance
  class Sources
    def self.slug(employer,provider) = "compliance-#{employer.id}-#{provider}"
    def self.fetch(monitor)
      credential = LightekVault::Service.checkout!(slug: slug(monitor.employer,monitor.provider),consumer: name,purpose: 'jurisdiction_monitoring',requested_by: "employer:#{monitor.employer_id}")
      key = credential.fetch('api_key')
      if monitor.provider == 'openstates'
        query = URI.encode_www_form(jurisdiction: "ocd-jurisdiction/country:us/state:#{monitor.state.downcase}/government",q: monitor.query,per_page: 20,page: 1)
        response = LightekIdentity::PublicHttp.json("https://v3.openstates.org/bills?#{query}",headers: {'X-API-KEY'=>key})
        rows = response.fetch('results').map do |item|
          {'title'=>item.fetch('title'),'identifier'=>item['identifier'],'status'=>item.dig('latest_action','description'),
            'source_url'=>safe_url(item['openstates_url']),'kind'=>'legislative_activity'}
        end
        {'items'=>rows,'scope'=>'First 20 matching legislative items; refine your query for broader result sets. Bill activity is not a finding that a law is effective.',
          'provider'=>'Open States API v3','checked_at'=>Time.current.iso8601,'review_status'=>'needs_review'}
      else
        raise ArgumentError,'New York statutes require NY' unless monitor.state == 'NY'
        query = URI.encode_www_form(term: monitor.query,limit: 20,key: key)
        response = LightekIdentity::PublicHttp.json("https://legislation.nysenate.gov/api/3/laws/search?#{query}")
        raise ArgumentError,'State source did not return a successful response' unless response['success'] == true
        values = response.fetch('result').fetch('items')
        values = values.fetch('items') if values.is_a?(Hash)
        rows = Array(values).map do |item|
          document = item['result'] || item
          law = document['lawId'].to_s
          location = document['locationId'].to_s
          source = law.match?(/\A[A-Z]{3}\z/) ? "https://www.nysenate.gov/legislation/laws/#{law}" : 'https://legislation.nysenate.gov/'
          source += "/#{URI.encode_www_form_component(location)}" if location.present? && law.match?(/\A[A-Z]{3}\z/)
          {'title'=>document['title'] || document['docType'] || law,'identifier'=>document['documentId'] || law,
            'source_url'=>source,'kind'=>'published_law_document','published_on'=>document['publishedDate']}
        end
        {'items'=>rows,'scope'=>'First 20 matching New York law documents. Review source text, effective dates and applicability.',
          'provider'=>'New York Senate Open Legislation API 3','checked_at'=>Time.current.iso8601,'review_status'=>'needs_review'}
      end
    ensure
      credential&.each_value { |v| v.clear if v.is_a?(String) && !v.frozen? }
    end
    def self.safe_url(value)
      uri=URI.parse(value.to_s)
      uri.scheme == 'https' && uri.host && !uri.userinfo ? uri.to_s : nil
    rescue URI::InvalidURIError
      nil
    end
  end
end

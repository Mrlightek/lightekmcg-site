# frozen_string_literal: true

class Api::BroadcastCarriageController < Api::ReservationFederationController
  rescue_from ActiveRecord::RecordNotUnique do
    render json: { error: "That carriage reference already exists." }, status: :conflict
  end

  def save
    values = params.permit(:name, :description, :published, :withdrawn, :renew, schedule: %i[title starts_at ends_at on_air]).to_h
    render json: Studio::Broadcasting::InstallationCarriage.receive!(@peer, params[:key], values)
  end

  def agreements
    records = hosted_agreements.includes(:outlet_site, :hosted_carriage).order(id: :desc).limit(100).map do |row|
      contract = Studio::Broadcasting::BroadcastContract.find_by(carriage_agreement_id: row.id, site_id: row.outlet_site_id)
      version = contract&.versions&.order(number: :desc)&.first
      row.station_receipt.merge("contract" => version && { "title" => contract.title, "ends_on" => version.ends_on.iso8601 })
    end
    render json: { agreements: records }
  end

  def accept_agreement
    agreement = hosted_agreements.find(params[:id])
    agreement.accept_from_peer!(@peer)
    render json: agreement.station_receipt
  end

  def contract
    agreement = hosted_agreements.find(params[:id])
    contract = Studio::Broadcasting::BroadcastContract.find_by(carriage_agreement: agreement)
    unless contract
      return render json: { agreement_id: agreement.id, current: nil, versions: [],
        report: Studio::Broadcasting::ContractReport.new(carriage: agreement).snapshot }
    end

    versions = contract.versions.includes(:signatures).order(number: :desc)
    current = versions.first
    render json: {
      agreement_id: contract.carriage_agreement_id, current: current.id,
      versions: versions.map { |version| { id: version.id, number: version.number, executed: version.executed?,
        withdrawn: version.withdrawn_at?, digest: version.document_digest, signed: version.signatures.any? { |row| row.party == "counterparty" } } },
      report: Studio::Broadcasting::ContractReport.new(version: current).snapshot
    }
  end

  def sign_contract
    values = params.require(:signature).permit(:version_id, :name, :digest, :consent)
    raise ArgumentError, "Confirm your intent to sign." unless values[:consent] == "1"

    version = hosted_contract.versions.find(values[:version_id])
    version.sign!(actor: @peer.merchant, party: "counterparty", name: values[:name], digest: values[:digest])
    render json: { executed: version.executed? }
  end

  def legacy_contract_report
    agreement = hosted_agreements.find(params[:id])
    render json: { report: Studio::Broadcasting::ContractReport.new(carriage: agreement).snapshot }
  end

  def contract_report
    version = hosted_contract.versions.find(params[:version_id])
    render json: { report: Studio::Broadcasting::ContractReport.new(version: version).snapshot }
  end

  def contract_copy
    render json: { copy: hosted_contract.versions.find(params[:version_id]).executed_copy }
  end

  private

  def hosted_contract
    agreement = hosted_agreements.find(params[:id])
    Studio::Broadcasting::BroadcastContract.find_by!(carriage_agreement: agreement, site_id: agreement.outlet_site_id)
  end

  def hosted_agreements
    Studio::Broadcasting::CarriageAgreement.where(station_site_id: @peer.site_id,
      hosted_carriage_id: Studio::Broadcasting::HostedCarriage.where(peer: @peer).select(:id))
  end
end

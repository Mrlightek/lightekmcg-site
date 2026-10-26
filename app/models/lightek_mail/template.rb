module LightekMail
  class Template < ApplicationRecord
    self.table_name = "lightek_mail_templates"
    belongs_to :account, class_name: "LightekMail::Account"
    validates :name, length: {in: 1..120}
    validates :subject, length: {in: 1..200}, format: {without: /[\r\n]/}
    before_validation do
      self.document = TemplateRenderer.normalize(document)
      TemplateRenderer.render(document)
      TemplateRenderer.interpolate(subject, {})
    end
  end
end

(() => {
  const initialize = () => {
    document.querySelectorAll('[data-marketplace-editor]').forEach(root => {
      if (root.dataset.marketplaceEnhanced) return
      root.dataset.marketplaceEnhanced = 'true'
      const update = () => {
        const billing = root.querySelector('[data-billing]')
        if (billing) {
          const type = billing.value
          root.querySelectorAll('[data-price-field]').forEach(el => {
            el.hidden = !((type === 'both' && ['monthly','annual'].includes(el.dataset.priceField)) || type === el.dataset.priceField)
          })
          root.querySelector('[data-setup-field]').hidden = type === 'free'
          root.querySelector('[data-trial-field]').hidden = !['monthly','annual','both'].includes(type)
          if (!['monthly','annual','both'].includes(type)) root.querySelector('[name="marketplace_product[trial_days]"]').value = '0'
        }
        const delivery = root.querySelector('[data-delivery]')
        if (delivery) root.querySelectorAll('[data-delivery-panel]').forEach(el => el.hidden = el.dataset.deliveryPanel !== delivery.value)
        const choice = root.querySelector('[data-service-choice]')
        if (choice) {
          const out = root.querySelector('[data-service-explanation]')
          const selected = choice.selectedOptions[0]
          out.replaceChildren()
          const text = document.createElement('p')
          text.textContent = selected && selected.value ? selected.dataset.description + ' Customer opens: ' + selected.dataset.path : 'Choose an application that you have reviewed and connected.'
          out.append(text)
        }
        const name = root.querySelector('[data-preview-name]'), description = root.querySelector('[data-preview-description]')
        if (name) root.querySelector('[data-live-name]').textContent = name.value || 'Your product name'
        if (description) root.querySelector('[data-live-description]').textContent = description.value || 'Your product description'
      }
      root.addEventListener('input', update)
      root.addEventListener('change', update)
      update()
    })
  }
  document.addEventListener('DOMContentLoaded', initialize)
  document.addEventListener('turbo:load', initialize)
  initialize()
})()

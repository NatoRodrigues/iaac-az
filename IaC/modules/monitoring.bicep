param location string = resourceGroup().location

param alertEmail string
param idleWebhookUri string = ''

param vmDevId string
param vmProdId string

param cpuThreshold int = 5
param alertWindowSize string = 'PT1H'
param evaluationFrequency string = 'PT15M'

//////////////////////////////////// ACTION GROUP ////////////////////////////////////

resource idleActionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: 'ag-idle-resources'
  location: 'global'

  tags: {
    Project: 'ops-toolkit'
    Monitoring: 'Enabled'
    Purpose: 'IdleResourceAlerts'
  }

  properties: {
    enabled: true
    groupShortName: 'idle'

    emailReceivers: [
      {
        name: 'Admin'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]

    webhookReceivers: empty(idleWebhookUri) ? [] : [
      {
        name: 'IdleReportWebhook'
        serviceUri: idleWebhookUri
        useCommonAlertSchema: true
      }
    ]
  }
}

//////////////////////////////////// VM DEV ALERT ////////////////////////////////////

resource vmDevLowCpu 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-vm-dev-low-cpu'
  location: 'global'

  tags: {
    Environment: 'Dev'
    Project: 'ops-toolkit'
    Monitoring: 'Enabled'
  }

  properties: {
    description: 'Possible idle VM based on low CPU.'
    severity: 3
    enabled: true
    autoMitigate: true

    scopes: [
      vmDevId
    ]

    evaluationFrequency: evaluationFrequency
    windowSize: alertWindowSize

    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location

    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'

      allOf: [
        {
          name: 'LowCpu'
          criterionType: 'StaticThresholdCriterion'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          operator: 'LessThan'
          threshold: cpuThreshold
          timeAggregation: 'Average'
          skipMetricValidation: false
          dimensions: []
        }
      ]
    }

    actions: [
      {
        actionGroupId: idleActionGroup.id
      }
    ]
  }
}

//////////////////////////////////// VM PROD ALERT ////////////////////////////////////

resource vmProdLowCpu 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-vm-prod-low-cpu'
  location: 'global'

  tags: {
    Environment: 'Prod'
    Project: 'ops-toolkit'
    Monitoring: 'Enabled'
  }

  properties: {
    description: 'Possible idle VM based on low CPU.'
    severity: 2
    enabled: true
    autoMitigate: true

    scopes: [
      vmProdId
    ]

    evaluationFrequency: evaluationFrequency
    windowSize: alertWindowSize

    targetResourceType: 'Microsoft.Compute/virtualMachines'
    targetResourceRegion: location

    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'

      allOf: [
        {
          name: 'LowCpu'
          criterionType: 'StaticThresholdCriterion'
          metricNamespace: 'Microsoft.Compute/virtualMachines'
          metricName: 'Percentage CPU'
          operator: 'LessThan'
          threshold: cpuThreshold
          timeAggregation: 'Average'
          skipMetricValidation: false
          dimensions: []
        }
      ]
    }

    actions: [
      {
        actionGroupId: idleActionGroup.id
      }
    ]
  }
}

//////////////////////////////////// OUTPUTS ////////////////////////////////////

output actionGroupId string = idleActionGroup.id

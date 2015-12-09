/* Copyright (C) 2014, 2015 BMW Group
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.genivi.commonapi.someip.generator

import java.io.File
import java.util.HashSet
import java.util.LinkedList
import java.util.List
import java.util.Map
import java.util.Set
import javax.inject.Inject
import org.eclipse.core.resources.IResource
import org.eclipse.emf.ecore.resource.Resource
import org.eclipse.xtext.generator.IFileSystemAccess
import org.eclipse.xtext.generator.IGenerator
import org.franca.core.franca.FModel
import org.franca.deploymodel.core.FDeployedInterface
import org.franca.deploymodel.core.FDeployedTypeCollection
import org.franca.deploymodel.dsl.fDeploy.FDInterface
import org.franca.deploymodel.dsl.fDeploy.FDModel
import org.franca.deploymodel.dsl.fDeploy.FDProvider
import org.franca.deploymodel.dsl.fDeploy.FDTypes
import org.genivi.commonapi.core.generator.FDeployManager
import org.genivi.commonapi.core.generator.FrancaGeneratorExtensions
import org.genivi.commonapi.someip.deployment.PropertyAccessor
import org.genivi.commonapi.someip.preferences.FPreferencesSomeIP
import org.genivi.commonapi.someip.preferences.PreferenceConstantsSomeIP

class FrancaSomeIPGenerator implements IGenerator {
    @Inject private extension FrancaGeneratorExtensions
    @Inject private extension FrancaSomeIPGeneratorExtensions
    @Inject private extension FInterfaceSomeIPProxyGenerator
    @Inject private extension FInterfaceSomeIPStubAdapterGenerator
    @Inject private extension FInterfaceSomeIPDeploymentGenerator
    
    @Inject private FDeployManager fDeployManager

    val String SOMEIP_SPECIFICATION_TYPE = "someip.deployment"
    val String CORE_SPECIFICATION_TYPE = "core.deployment"
        
    override doGenerate(Resource input, IFileSystemAccess fileSystemAccess) {
        if (!input.URI.fileExtension.equals(FDeployManager.fileExtension)) {
                return
        }

        var List<FDInterface> deployedInterfaces = new LinkedList<FDInterface>()
        var List<FDTypes> deployedTypeCollections = new LinkedList<FDTypes>()
        var List<FDProvider> deployedProviders = new LinkedList<FDProvider>()
        var IResource res = null

        var rootModel = fDeployManager.loadModel(input.URI, input.URI);
        
        generatedFiles_ = new HashSet<String>()
        
        withDependencies_ = FPreferencesSomeIP::instance.getPreference(
            PreferenceConstantsSomeIP::P_GENERATE_DEPENDENCIES_SOMEIP, "true"
        ).equals("true")
        
        // models holds the map of all models from imported .fidl files
        var models = fDeployManager.fidlModels
        // deployments holds the map of all models from imported .fdepl files
        var deployments = fDeployManager.deploymentModels
        
        if (rootModel instanceof FDModel) {
            deployments.put(input.URI.toString , rootModel)
        } else {
            System.err.println("CommonAPI-SomeIP requires a deployment model!")
            return
        }
     
        for (itsEntry : deployments.entrySet) {
            val itsDeployment = itsEntry.value
           
            // Get Core deployments
            val itsCoreInterfaces = getFDInterfaces(itsDeployment, CORE_SPECIFICATION_TYPE)
            val itsCoreTypeCollections = getFDTypesList(itsDeployment, CORE_SPECIFICATION_TYPE)
            
            // Get SOME/IP deployments
            val itsSomeIPInterfaces = getFDInterfaces(itsDeployment, SOMEIP_SPECIFICATION_TYPE)
            val itsSomeIPTypeCollections = getFDTypesList(itsDeployment, SOMEIP_SPECIFICATION_TYPE)
            val itsSomeIPProviders = getFDProviders(itsDeployment, SOMEIP_SPECIFICATION_TYPE)
            
            // Merge Core deployments for interfaces to their SOME/IP deployments
            for (itsSomeIPDeployment : itsSomeIPInterfaces)
                for (itsCoreDeployment : itsCoreInterfaces)
                    mergeDeployments(itsCoreDeployment, itsSomeIPDeployment)

            // Merge Core deployments for type collections to their SOME/IP deployments
            for (itsSomeIPDeployment : itsSomeIPTypeCollections)
                for (itsCoreDeployment : itsCoreTypeCollections)
                    mergeDeployments(itsCoreDeployment, itsSomeIPDeployment)
                    
            deployedInterfaces.addAll(itsSomeIPInterfaces)
            deployedTypeCollections.addAll(itsSomeIPTypeCollections)
            deployedProviders.addAll(itsSomeIPProviders)                    
        }  

        doGenerateDeployment(rootModel as FDModel, deployments, models,
            deployedInterfaces, deployedTypeCollections, deployedProviders,
            fileSystemAccess, res)
            
        fDeployManager.clearFidlModels
        fDeployManager.clearDeploymentModels            
    }
    
    def private void doGenerateDeployment(FDModel _deployment,
                                          Map<String, FDModel> _deployments,
                                          Map<String, FModel> _models,
                                          List<FDInterface> _interfaces,
                                          List<FDTypes> _typeCollections,
                                          List<FDProvider> _providers,
                                          IFileSystemAccess _access,
                                          IResource _res) {
        val String deploymentName
            = _deployments.entrySet.filter[it.value == _deployment].head.key
        
        var int lastIndex = deploymentName.lastIndexOf(File.separatorChar)
        if (lastIndex == -1) {
            lastIndex = deploymentName.lastIndexOf('/')
        }

        var String basePath = deploymentName.substring(
            0, lastIndex)
            
        var Set<String> itsImports = new HashSet<String>()
        for (anImport : _deployment.imports) {
            val String cannonical = basePath.getCanonical(anImport.importURI)
            itsImports.add(cannonical)
        }                                               
                
        if (withDependencies_) {
            for (itsEntry : _deployments.entrySet) {
                if (itsImports.contains(itsEntry.key)) {
                    doGenerateDeployment(itsEntry.value, _deployments, _models,
                        _interfaces, _typeCollections, _providers,
                        _access, _res)
                }                                
            }
        }
        
        for (itsEntry : _models.entrySet) {
            if (itsImports.contains(itsEntry.key)) {
                doGenerateModel(itsEntry.value, _models,
                    _interfaces, _typeCollections, _providers,
                    _access, _res)
            }    
        }                        
    }

    def private void doGenerateModel(FModel _model,
                                     Map<String, FModel> _models,
                                     List<FDInterface> _interfaces,
                                     List<FDTypes> _typeCollections,
                                     List<FDProvider> _providers,
                                     IFileSystemAccess _access,
                                     IResource _res) {
        val String modelName
            = _models.entrySet.filter[it.value == _model].head.key
            
        if (generatedFiles_.contains(modelName)) {
            return
        }       
        
        generatedFiles_.add(modelName)
                
        doGenerateComponents(_model,
            _interfaces, _typeCollections, _providers,
            _access, _res)
            
        if (withDependencies_) {
            for (itsEntry : _models.entrySet) {
                var FModel itsModel = itsEntry.value
                if (itsModel != null) {
                    doGenerateComponents(itsModel,
                        _interfaces, _typeCollections, _providers,
                        _access, _res)
                }
            }            
        }                       
    }
    
    def private doGenerateComponents(FModel _model,
                                     List<FDInterface> _interfaces,
                                     List<FDTypes> _typeCollections,
                                     List<FDProvider> _providers,
                                     IFileSystemAccess fileSystemAccess,
                                     IResource res) {
        
        val defaultDeploymentAccessor = new PropertyAccessor()
        
        _model.typeCollections.forEach [
            var PropertyAccessor typeCollectionDeploymentAccessor
            val currentTypeCollection = it
            if (_typeCollections.exists[it.target == currentTypeCollection]) {
                typeCollectionDeploymentAccessor = new PropertyAccessor(
                    new FDeployedTypeCollection(_typeCollections.filter[it.target == currentTypeCollection].last))
            } else {
                typeCollectionDeploymentAccessor = defaultDeploymentAccessor
            }
            insertAccessor(currentTypeCollection, typeCollectionDeploymentAccessor)
        ]

        _model.interfaces.forEach [
            var PropertyAccessor interfaceDeploymentAccessor
            val currentInterface = it
            if (_interfaces.exists[it.target == currentInterface]) {
                interfaceDeploymentAccessor = new PropertyAccessor(
                    new FDeployedInterface(_interfaces.filter[it.target == currentInterface].last))
            } else {
                interfaceDeploymentAccessor = defaultDeploymentAccessor
            }
            insertAccessor(currentInterface, interfaceDeploymentAccessor)
        ]
        
        var typeCollectionsToGenerate = _model.typeCollections.toSet
        var interfacesToGenerate = _model.interfaces.toSet
            
        typeCollectionsToGenerate.forEach [
            it.generateTypeCollectionDeployment(fileSystemAccess, getAccessor(it), res)
        ]

        interfacesToGenerate.forEach [
            var PropertyAccessor interfaceAccessor = getAccessor(it)
            if (FPreferencesSomeIP::instance.getPreference(PreferenceConstantsSomeIP::P_GENERATEPROXY_SOMEIP, "true").
                equals("true")) {
                it.generateProxy(fileSystemAccess, interfaceAccessor, _providers, res)
            }
            if (FPreferencesSomeIP::instance.getPreference(PreferenceConstantsSomeIP::P_GENERATESTUB_SOMEIP, "true").
                equals("true")) {
                it.generateStubAdapter(fileSystemAccess, interfaceAccessor, _providers, res)
            }
            if (FPreferencesSomeIP::instance.getPreference(PreferenceConstantsSomeIP::P_GENERATE_COMMON_SOMEIP, "true").
                equals("true")) {
                it.generateDeployment(fileSystemAccess, interfaceAccessor, res)
            }
            it.managedInterfaces.forEach [
                val currentManagedInterface = it
                var PropertyAccessor managedDeploymentAccessor
                if (_interfaces.exists[it.target == currentManagedInterface]) {
                    managedDeploymentAccessor = new PropertyAccessor(
                        new FDeployedInterface(_interfaces.filter[it.target == currentManagedInterface].last))
                } else {
                    managedDeploymentAccessor = new PropertyAccessor()
                }
                it.generateProxy(fileSystemAccess, managedDeploymentAccessor, _providers, res)
                it.generateStubAdapter(fileSystemAccess, managedDeploymentAccessor, _providers, res)
            ]
        ]
    }

    private var boolean withDependencies_;
    private var Set<String> generatedFiles_;
}

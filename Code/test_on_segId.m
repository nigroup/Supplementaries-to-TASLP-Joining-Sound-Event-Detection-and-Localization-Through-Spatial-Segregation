function test_on_segId( dd, cc, scps, azmSigm, nsbias )

startTwoEars('util/tt_segmented.config.xml');
addpath( fullfile( pwd, 'util' ) );

if nargin < 4 || isempty(azmSigm), azmSigm = 0; end
if nargin < 5 || isempty(nsbias), nsbias = 0; end

nigensPath = 'twoears/NIGENS'; % TODO: put your own NIGENS path
dataCachePath = 'twoears/idPipeCache'; % TODO: put your own (absolute!) AMLTTP cache path

segIdSuplStr = [num2str( azmSigm ) '-' num2str( nsbias )];
savemat = fullfile( pwd, '../testdata', ['segId.on.segId_' segIdSuplStr '.test'] );

segmModelFileName = '70c4feac861e382413b4c4bfbf895695.mat';
mkdir( fullfile( db.tmp, 'learned_models', 'SegmentationKS' ) );
copyfile( ['../spatial_segregation_model/' segmModelFileName], ...
          fullfile( db.tmp, 'learned_models', 'SegmentationKS', segmModelFileName ), ...
          'f' );

datasets = {fullfile( nigensPath, 'NIGENS_8-foldSplit_fold1_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_8-foldSplit_fold2_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_8-foldSplit_fold3_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_8-foldSplit_fold4_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_8-foldSplit_fold5_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_8-foldSplit_fold6_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_8-foldSplit_fold7_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_8-foldSplit_fold8_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_minidebug_8-foldSplit_fold1_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_minidebug_8-foldSplit_fold2_wo_timit.flist' ),...
            fullfile( nigensPath, 'NIGENS_minidebug_8-foldSplit_fold7_wo_timit.flist' )};
if nargin < 1 || isempty( dd )
    dd = 7:8;
end

classes = {{'alarm'},{'baby'},{'femaleSpeech'},{'fire'},{'crash'},{'dog'},...
           {'engine'},{'footsteps'},{'knock'},{'phone'},{'piano'},...
           {'maleSpeech'},{'femaleScream','maleScream'}};
           
for ii = 1 : numel( classes )
    labelCreators{ii,1} = 'LabelCreators.MultiEventTypeLabeler'; %#ok<AGROW>
    labelCreators{ii,2} = {'types', classes(ii), 'negOut', 'rest', ...
                           'removeUnclearBlocks', 'time-wise',...
                           'segIdTargetSrcFilter', [1,1]}; %#ok<AGROW> % target sounds only on source 1
end
if nargin < 2 || isempty( cc ), cc = 1 : size( labelCreators, 1 ); end
           
scc = getTestSceneParametersMc7();
if nargin < 3 || isempty( scps ), scps = 1 : numel( scc ); end

doneCfgsTest = {};
modelpathes_test = cell( 0, 0 ); % ll,scp
if exist( [savemat '.mat'], 'file' )
    load( [savemat '.mat'] );
end

    
pipe = TwoEarsIdTrainPipe( 'cacheSystemDir', dataCachePath, ...
                           'cacheDirectoryDirSuppl', segIdSuplStr, 'cddsUseIdxs', [4,5,6] );
pipe.blockCreator = BlockCreators.MeanStandardBlockCreator( 0.5, 1./3 );
pipe.ksWrapper = DataProcs.SegmentKsWrapper( ...
        '../spatial_segregation_model/SegmentationTrainerParameters5.yaml', ...
        'useDnnLocKs', false, ...
        'useNsrcsKs', false, ...
        'segSrcAssignmentMethod', 'minDistance', ...
        'varAzmSigma', azmSigm, ...
        'nsrcsBias', nsbias, ...
        'nsrcsRndPlusMinusBias', 0, ...
        'srcSegregateNrjThreshold', -40, ...
        'softMaskExponent', 10 ); % should be the same as featureCreator's compressor
pipe.featureCreator = FeatureCreators.FeatureSet5bBlockmean();

for ll = cc

    pipe.labelCreator = feval( labelCreators{ll,1}, labelCreators{ll,2}{:} );
    pipe.modelCreator = ModelTrainers.LoadModelNoopTrainer( ...
        fullfile( pwd, '../segregated_detection_models', [strcat(classes{ll}{:}) '.model.mat'] ), ...
        'performanceMeasure', @PerformanceMeasures.BAC_BAextended, ...
        'dataSelector', DataSelectors.BAC_NPP_NS_Selector(), ...
        'importanceWeighter', ImportanceWeighters.IgnorantWeighter() );
    pipe.modelCreator.verbose( 'on' );
    PerformanceMeasures.BAC_BAextended.classList( [classes {{'general'}}] );

    pipe.setTestset( datasets(dd) );
    pipe.setupData();
    
    for scp = scps
        if any( cellfun( @(x)(all(x==[ll scp])), doneCfgsTest ) )
            continue;
        end

        fprintf( '\n\n============== testing %s model; dataset = %s, scp = %d ==============\n\n', ...
            strcat(classes{ll}{:}), num2str(dd), scp );
        fprintf( '\n======== azmSigm = %d, nsbias = %d. ========\n\n', ...
           azmSigm, nsbias );


        sc = SceneConfig.SceneConfiguration();
        sc.addSource( SceneConfig.PointSource( ...
                          'azimuth',SceneConfig.ValGen('manual',scc(scp).azms(1)), ...
                          'data', SceneConfig.FileListValGen( 'pipeInput' ) ) );
        for jj = 2 : scc(scp).nSrcs
            sc.addSource( SceneConfig.PointSource( ...
                              'azimuth',SceneConfig.ValGen('manual',scc(scp).azms(jj)), ...
                              'data', SceneConfig.MultiFileListValGen( pipe.srcDataSpec ),...
                              'offset', SceneConfig.ValGen( 'manual', 0.25 ) ), ...
                          'snr', SceneConfig.ValGen( 'manual', scc(scp).snrs(jj) ),...
                          'loop', 'randomSeq' );
        end
        sc.setLengthRef( 'source', 1, 'min', 30 );
        sc.setSceneNormalization( true, 1 );

        pipe.init( sc, 'fs', 16000, 'loadBlockAnnotations', true, ...
                       'classesOnMultipleSourcesFilter', classes, ...
                       'dataSelector', DataSelectors.BAC_NPP_NS_Selector(),...
                       'trainerFeedDataType', @single, 'pipeReUse', 5 );

        pipe.pipeline.dataPipeProcs{1}.dataFileProcessor.procCacheFolderNames = 'mc_test';
        pipe.pipeline.dataPipeProcs{2}.dataFileProcessor.procCacheFolderNames = 'mc_test';
        pipe.pipeline.dataPipeProcs{4}.dataFileProcessor.procCacheFolderNames = ...
                                                   ['mc_segId_' segIdSuplStr '_test'];
        pipe.pipeline.dataPipeProcs{5}.dataFileProcessor.procCacheFolderNames = ...
                                                   ['mc_segId_' segIdSuplStr '_test'];
        pipe.pipeline.dataPipeProcs{6}.dataFileProcessor.procCacheFolderNames = ...
                                                   ['mc_segId_fc5b_' segIdSuplStr '_test'];

        [modelpathes_test{ll,scp},~,testPerfresults] = pipe.pipeline.run( 'modelName', ...
                                                                          strcat(classes{ll}{:}) );
        test_performances_b{ll,scp} = testPerfresults.strapOffDpi(); %#ok<NASGU,AGROW>
        mp = pathInsert( modelpathes_test{ll,scp}, 'testRuns', 0 );
        movefile( modelpathes_test{ll,scp}, mp );

        doneCfgsTest{end+1} = [ll scp]; %#ok<AGROW>

        if (mod(scp,20) == 0) || (scp == scps(end))
            if ~exist( fullfile( pwd, '../testdata' ), 'dir' )
                mkdir( fullfile( pwd, '../testdata' ) );
            end
            save( [savemat '.mat'], ...
                'doneCfgsTest', 'modelpathes_test','test_performances_b', ...
                '-v7.3' );
            fprintf( ';\n' );
        end

    end
end

end


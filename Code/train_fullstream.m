function train_fullstream( dd, cc, scps )

startTwoEars('util/tt_general.config.xml');

nigensPath = 'twoears/NIGENS'; % TODO: put your own NIGENS path
dataCachePath = 'twoears/idPipeCache'; % TODO: put your own (absolute!) AMLTTP cache path


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
    dd = 1:6;
end

classes = {{'alarm'},{'baby'},{'femaleSpeech'},{'fire'},{'crash'},{'dog'},...
           {'engine'},{'footsteps'},{'knock'},{'phone'},{'piano'},...
           {'maleSpeech'},{'femaleScream','maleScream'}};
           
for ii = 1 : numel( classes )
    labelCreators{ii,1} = 'LabelCreators.MultiEventTypeLabeler'; %#ok<AGROW>
    labelCreators{ii,2} = {'types', classes(ii), 'negOut', 'rest', ...
                           'removeUnclearBlocks', 'block-wise'}; %#ok<AGROW>
end
if nargin < 2 || isempty( cc ), cc = 1 : size( labelCreators, 1 ); end
           
scc = load( 'util/trainSceneParams.mat' );
scc = scc.scp;
if nargin < 3 || isempty( scps ), scps = 1 : numel( scc ); end

for ll = cc
    fprintf( '\n\n============== training fullstream mc %s model; dataset(s) = %s ==============\n\n', ...
        strcat(classes{ll}{:}), num2str( dd ) );
    
    pipe = TwoEarsIdTrainPipe( 'cacheSystemDir', dataCachePath );
    pipe.blockCreator = BlockCreators.MeanStandardBlockCreator( 0.5, 1./3 );
    pipe.featureCreator = FeatureCreators.FeatureSet5cBlockmean();
    pipe.labelCreator = feval( labelCreators{ll,1}, labelCreators{ll,2}{:} );
    pipe.modelCreator = ModelTrainers.GlmNetLambdaSelectTrainer( ...
        'performanceMeasure', @PerformanceMeasures.ImportanceWeightedSquareBalancedAccuracy, ...
        'dataSelector', DataSelectors.BAC_NPP_NS_Selector(), ...
        'importanceWeighter', ImportanceWeighters.BAC_NS_NPP_Weighter(), ...
        'cvFolds', 'preFolded', ...
        'alpha', 0.99, ... % prevents numeric instabilities (compared to 1)
        'maxDataSize', 2e5 ); % GLMNET can't cope with more than 2GB
    ModelTrainers.CVtrainer.useParallelComputing( true );
    pipe.modelCreator.verbose( 'on' );

    pipe.setTrainset( datasets(dd) );
    pipe.setupData();
    
    sc = SceneConfig.SceneConfiguration.empty;
    for scp = scps
        sc(end+1) = SceneConfig.SceneConfiguration(); %#ok<AGROW>
        sc(end).addSource( SceneConfig.PointSource( ...
            'azimuth',SceneConfig.ValGen('manual',scc(scp).azms(1)), ...
            'data', SceneConfig.FileListValGen( 'pipeInput' ) )...
            );
        for jj = 2 : scc(scp).nSrcs
            sc(end).addSource( SceneConfig.PointSource( ...
                    'azimuth',SceneConfig.ValGen('manual',scc(scp).azms(jj)), ...
                    'data', SceneConfig.MultiFileListValGen( pipe.srcDataSpec ),...
                    'offset', SceneConfig.ValGen( 'manual', 0.25 ) ), ...
                'snr', SceneConfig.ValGen( 'manual', scc(scp).snrs(jj) ),...
                'loop', 'randomSeq' ...
                );
        end
        sc(end).setLengthRef( 'source', 1, 'min', 30 );
        sc(end).setSceneNormalization( true, 1 );
    end
    pipe.init( sc, 'fs', 16000, 'loadBlockAnnotations', true, ...
              'classesOnMultipleSourcesFilter', classes, ...
              'nSamplesPerSceneInstance', ceil( 1.5e5 / (730*80) ), ...
              'nSamplesPerTargetSceneInstance', ceil( 1.5e5 / (40*80) ), ...
              'selectTargetLabel', 1, ...
              'dataSelector', DataSelectors.BAC_NPP_NS_Selector(), ...
              'trainerFeedDataType', @single );
    
    pipe.pipeline.dataPipeProcs{1}.dataFileProcessor.procCacheFolderNames = 'mc_train';
    pipe.pipeline.dataPipeProcs{2}.dataFileProcessor.procCacheFolderNames = 'mc_train';
    pipe.pipeline.dataPipeProcs{4}.dataFileProcessor.procCacheFolderNames = 'mc_fullstream_train';
    pipe.pipeline.dataPipeProcs{5}.dataFileProcessor.procCacheFolderNames = 'mc_fullstream_fc5c_train';
          
    mp = pipe.pipeline.run( 'modelName', strcat(classes{ll}{:}) );
    movefile( fullfile( mp, '*.model.mat' ), fullfile( pwd, '../fullstream_detection_models' ) );
    try
        pause(1);
        rmdir( mp, 's' );
    catch ex
        warning( ex.message );
    end
end

end

function Spk = LoaddataSpk(loadparams, sampleTimes)
% Spk = LoaddataSpk(loadparams, sampleTimes)
%
%Load spiking data into Spk structure, resampled according to timestamps
%provided in sampleTimes and other parameters defined in loadparams. See
%DefineLoadParams.m for a description of those parameters.
%
% INPUT:
% - loadparams:  a structure whose fields contain the parameters necessary
% to load the spiking data data and resample them.
% See DefineLoadParams.m for a description of these parameters.
%
% OUTPUT:
% - Spk: a matlab structure whose fields contain the different types of
% behavioral data resampled at the desired sampling rate (defined in
% loadparams.samplingRate).
%
% Fields of Nav are the following:
% - sampleTimes: time stamps of the resampled spike trains
%
% - spikeTimes: a ntimes x 1 array of all spike times
%
% - spikeID: cluster IDs of spikes in spikeTimes
%
% - spikeTrain: a nTimes x nCells array of spike counts in bins centered
% around sample times of Spk.sampleTimes
%
% - shankID: 1 x nCells array of ID of the shank where each cluster was 
% recorded
%
% - PyrCell: 1 x nCells logical array. true if the cluster is a putative
% Pyramidal neuron
%
% - IntCell: 1 x nCells logical array. true if the cluster is a putative
% interneuron
%
% - hpcCell: 1 x nCells logical array. true if the cluster is in hpc
%
% - blaRCell: 1 x nCells logical array. true if the cluster is in right bla
%
% - blaLCell: 1 x nCells logical array. true if the cluster is in left bla
%
% - ripple: ntimes x 1 array with ones wherever there is a ripple.
%
% - ripplepeak: ntimes x 1 array with ones for ripple peaks.
%
% - rippleTimes: timestamps of the detected ripple peaks (in seconds)
%
% USAGE:
%  Spk = LoaddataSpk(loadparams, sampleTimes)
%
%
% written by J.Fournier 08/2023 for the iBio Summer school

%%
%loading spike times and cluster ID from the prepared .mat file
S = load([loadparams.Datafolder filesep loadparams.spkfilename]);

%Removing spikes that are before or after behavior started
extraspk = S.AllSpikes(:,1) < sampleTimes(1) | S.AllSpikes(:,1) > sampleTimes(end);
S.AllSpikes(extraspk,:) = [];

%keep only cells that were either in hpc or bla
%Saving some cluster info into the Spk structure
info = load([loadparams.Datafolder filesep loadparams.spkinfofilename]);
hpcblaClustidx = ismember(info.IndexType(:,3), [loadparams.ShankList_hpc loadparams.ShankList_blaL loadparams.ShankList_blaR]);

%Saving spike times and cluster IDs.
Spk.spikeTimes = S.AllSpikes(:,1);% - Nav.sampleTimes(1);
Spk.spikeID = S.AllSpikes(:,2);

%Keeping only cells in hpc or bla
goodspkidx = ismember(Spk.spikeID,find(hpcblaClustidx));
Spk.spikeTimes = Spk.spikeTimes(goodspkidx);
Spk.spikeID = Spk.spikeID(goodspkidx);

%convert spike times into an array of spike trains, sampled according to 
%sampleTimes.
clustList = unique(Spk.spikeID);
ncells = numel(clustList);
nTimeSamples = numel(sampleTimes);
sampleRate = 1 / mean(diff(sampleTimes));

Spk.spikeTrain = zeros(nTimeSamples, ncells);
binEdges = [sampleTimes ; max(sampleTimes) + 1/sampleRate];

for icell = 1:ncells
    s = S.AllSpikes(S.AllSpikes(:,2) == clustList(icell),1);
    Spk.spikeTrain(:,icell) = histcounts(s, binEdges);
end
Spk.sampleTimes = sampleTimes;

%Saving some cluster info into the Spk structure
Spk.shankID = info.IndexType(hpcblaClustidx,3)';
Spk.PyrCell = (info.IndexType(hpcblaClustidx,6) == 1)';
Spk.IntCell = (info.IndexType(hpcblaClustidx,6) == 2)';
Spk.hpcCell = ismember(Spk.shankID,loadparams.ShankList_hpc);
Spk.blaLCell = ismember(Spk.shankID,loadparams.ShankList_blaL);
Spk.blaRCell = ismember(Spk.shankID,loadparams.ShankList_blaR);

%%
%loading ripples timestamps and filling in Spk.ripple with 1 when there
%is a ripple and Spk.ripplepeak with 1 for the peak of each ripple
Spk.ripple = zeros(numel(sampleTimes),1);
Spk.ripplepeak = zeros(numel(sampleTimes),1);

ripevents = LoadEvents([loadparams.Datafolder filesep loadparams.ripevtfilename]);
ripstart = ripevents.timestamps(contains(ripevents.description,'start'));
ripstop = ripevents.timestamps(contains(ripevents.description,'stop'));
rippeak = ripevents.timestamps(contains(ripevents.description,'peak'));

for idx = 1:numel(ripstart)
    Spk.ripple(sampleTimes >= ripstart(idx) & sampleTimes <= ripstop(idx)) = 1;
    [~, rippeakidx] = min(abs(sampleTimes - rippeak(idx)));
    Spk.ripplepeak(rippeakidx) = 1;
end

Spk.rippleTimes = rippeak;

end
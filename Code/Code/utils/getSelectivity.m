function selectivityIndex = getSelectivity(t)
% getSelectivity computes the selectivity index of a tuning curve.
%
% selectivityIndex = getSelectivity(t) computes the selectivity index of a
% tuning curve t as the difference between the maximal and minimal values
% normalized by the mean value of the tuning curve.
%
% INPUT:
% - t: Tuning curve representing firing rates.
%
% OUTPUT:
% - selectivityIndex: Selectivity index of the tuning curve.
%
% USAGE:
% selectivityIndex = getSelectivity(t);
%
%
% Written by J.Fournier 08/2023 for the iBio Summer school


selectivityIndex = (max(t(:)) - min(t(:))) / mean(t(:), 'omitnan');

end
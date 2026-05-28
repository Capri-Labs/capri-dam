import React, { createContext, useState, useContext } from 'react';

const ReportFilterContext = createContext();

export function ReportFilterProvider({ children }) {
    const [dateRange, setDateRange] = useState('last_30_days');
    const [departmentFilter, setDepartmentFilter] = useState('all');

    return (
        <ReportFilterContext.Provider value={{
            dateRange, setDateRange,
            departmentFilter, setDepartmentFilter
        }}>
            {children}
        </ReportFilterContext.Provider>
    );
}

export const useReportFilters = () => useContext(ReportFilterContext);